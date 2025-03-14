# frozen_string_literal: true

require 'fileutils'

module ExampleAppHelper
  def setup_example_app
    FileUtils.rm_rf(example_app_path)

    # Rails will not install within a directory containing `bin/rails`
    Rails.root.join("../bin/rails").rename(Rails.root.join("../bin/_rails")) if Rails.root.join("../bin/rails").exist?

    root_path = example_app_path.join('..')
    FileUtils.cd(root_path) do
      system <<~BASH, exception: true
        bundle exec rails new #{app_name} -d postgresql \
        --skip-action-text --skip-action-mailer --skip-action-mailbox --skip-action-cable --skip-git --skip-sprockets \
        --skip-listen --skip-javascript --skip-turbolinks --skip-solid --skip-kamal --skip-system-test --skip-test-unit \
        --skip-bootsnap --skip-spring --skip-active-storage
      BASH
    end

    FileUtils.rm_rf("#{example_app_path}/config/initializers/assets.rb")
    FileUtils.cp(::Rails.root.join('config/database.yml'), "#{example_app_path}/config/database.yml")

    File.open("#{example_app_path}/Gemfile", 'a') do |f|
      f.puts 'gem "good_job", path: "#{File.dirname(__FILE__)}/../../../"'
    end
  end

  def teardown_example_app
    Rails.root.join("../bin/_rails").rename(Rails.root.join("../bin/rails"))
    FileUtils.rm_rf(example_app_path)
  end

  def run_in_example_app(*args)
    FileUtils.cd(example_app_path) do
      system(*args) || raise("Command #{args} failed")
    end
  end

  def run_in_demo_app(*args)
    FileUtils.cd(Rails.root) do
      system(*args) || raise("Command #{args} failed")
    end
  end

  def within_example_app
    # Will be running database migrations from the newly created Example App
    # but doing so in the existing database. This resets the database so that
    # newly created migrations can be run, then resets it back.
    #
    # Ideally this would happen in a different database, but that seemed like
    # a lot of work to do in Github Actions.
    tables = %i[
      good_jobs
      good_job_batches
      good_job_executions
      good_job_processes
      good_job_settings
    ]
    models = [
      GoodJob::Job,
      GoodJob::Execution,
      GoodJob::BatchRecord,
      GoodJob::Process,
      GoodJob::Setting,
    ]
    quiet do
      tables.each do |table_name|
        ActiveRecord::Migration.drop_table(table_name) if ActiveRecord::Base.connection.table_exists?(table_name)
      end
      ActiveRecord::Base.connection.execute("TRUNCATE schema_migrations")

      setup_example_app
      run_in_demo_app("bin/rails db:environment:set RAILS_ENV=test")
      models.each(&:reset_column_information)
    end

    yield
  ensure
    quiet do
      teardown_example_app

      tables.each do |table_name|
        ActiveRecord::Migration.drop_table(table_name) if ActiveRecord::Base.connection.table_exists?(table_name)
      end
      ActiveRecord::Base.connection.execute("TRUNCATE schema_migrations")

      run_in_demo_app("bin/rails db:schema:load db:environment:set RAILS_ENV=test")
      models.each(&:reset_column_information)
    end
  end

  def example_app_path
    Rails.root.join('../tmp', app_name)
  end

  def app_name
    'example_app'
  end
end

RSpec.configure { |c| c.include ExampleAppHelper, type: :generator }
