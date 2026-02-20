require 'logger'
require 'fileutils'

module Chaussettes
  class Logger
    LOG_DIR = File.expand_path('~/.local/share/chaussettes/logs')
    LOG_FILE = File.join(LOG_DIR, 'chaussettes.log')

    class << self
      def instance
        @instance ||= create_logger
      end

      def debug(message)
        instance.debug(message)
      end

      def info(message)
        instance.info(message)
      end

      def warn(message)
        instance.warn(message)
      end

      def error(message)
        instance.error(message)
      end

      def fatal(message)
        instance.fatal(message)
      end

      private

      def create_logger
        ensure_log_directory

        logger = ::Logger.new(LOG_FILE, 10, 1_024_000) # 10 files, 1MB each
        logger.level = ::Logger::DEBUG
        logger.datetime_format = '%Y-%m-%d %H:%M:%S'
        logger.formatter = proc do |severity, datetime, _progname, msg|
          "[#{datetime}] #{severity.ljust(5)}: #{msg}\n"
        end

        logger
      rescue StandardError => e
        # Fallback to stderr if we can't create file logger
        logger = ::Logger.new(STDERR)
        logger.level = ::Logger::DEBUG
        logger.error("Failed to create file logger: #{e.message}")
        logger
      end

      def ensure_log_directory
        FileUtils.mkdir_p(LOG_DIR) unless File.directory?(LOG_DIR)
      rescue StandardError => e
        warn "Warning: Could not create log directory #{LOG_DIR}: #{e.message}"
      end
    end
  end
end
