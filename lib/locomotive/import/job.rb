require 'zip/zipfilesystem'

module Locomotive
  module Import
    class Job

      include Logger

      def initialize(zipfile, site, options = {})
        @site = site
        @options = {
          :reset    => false,
          :samples  => false,
          :enabled  => {}
        }.merge(options)

        @identifier = self.store_zipfile(zipfile)

        raise "Theme identifier not found" if @identifier.blank?
      end

      def before(worker)
        @worker = worker
      end

      def perform
        self.log "theme identifier #{@identifier}"

        self.unzip!

        raise "No database.yml found in the theme zipfile" if @database.nil?

        context = {
          :database => @database,
          :site => @site,
          :theme_path => @theme_path,
          :error => nil,
          :worker => @worker
        }

        self.reset! if @options[:reset]

        %w(site content_types assets asset_collections snippets pages).each do |step|
          if @options[:enabled][step] != false
            "Locomotive::Import::#{step.camelize}".constantize.process(context, @options)
            @worker.update_attributes :step => step if @worker
          else
            self.log "skipping #{step}"
          end
        end
      end

      def success(worker)
        self.log 'deleting original zip file'

        uploader = ThemeUploader.new(@site)

        uploader.retrieve_from_store!(@identifier)

        uploader.remove!

        self.log 'deleting working folder'

        FileUtils.rm_rf(themes_folder) rescue nil
      end

      protected

      def themes_folder
        File.join(Rails.root, 'tmp', 'themes', @site.id.to_s)
      end

      def prepare_folder
        FileUtils.rm_rf self.themes_folder if File.exists?(self.themes_folder)

        FileUtils.mkdir_p(self.themes_folder)
      end

      def store_zipfile(zipfile)
        return nil if zipfile.blank?

        file = CarrierWave::SanitizedFile.new(zipfile)

        uploader = ThemeUploader.new(@site)

        begin
          uploader.store!(file)
        rescue CarrierWave::IntegrityError
          return nil
        end

        uploader.identifier
      end

      def retrieve_zipfile
        uploader = ThemeUploader.new(@site)

        uploader.retrieve_from_store!(@identifier)

        if uploader.file.respond_to?(:url)
          self.log 'file from remote storage'

          @theme_file = File.join(self.themes_folder, @identifier)

          File.open(@theme_file, 'w') { |f| f.write(uploader.file.read) }
        else # local filesystem
          self.log 'file from local storage'

          @theme_file = uploader.path
        end
      end

      def unzip!
        self.prepare_folder

        self.retrieve_zipfile

        self.log "unzip #{@theme_file}"

        Zip::ZipFile.open(@theme_file) do |zipfile|
          destination_path = self.themes_folder

          zipfile.each do |entry|
            next if entry.name =~ /__MACOSX/

            if entry.name =~ /database.yml$/

              @database = YAML.load(zipfile.read(entry.name))
              @theme_path = File.join(destination_path, entry.name.gsub('database.yml', ''))

              next
            end

            FileUtils.mkdir_p(File.dirname(File.join(destination_path, entry.name)))

            zipfile.extract(entry, File.join(destination_path, entry.name))
          end
        end

      end

      def reset!
        @site.pages.destroy_all
        @site.theme_assets.destroy_all
        @site.content_types.destroy_all
        @site.asset_collections.destroy_all
      end

    end
  end
end