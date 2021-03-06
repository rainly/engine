module Locomotive
  module Import
    class Pages < Base

      def process
        context[:done] = {} # initialize the hash storing pages already processed

        self.add_index_and_404

        Dir[File.join(theme_path, 'templates', '**/*')].each do |template_path|

          fullpath = template_path.gsub(File.join(theme_path, 'templates'), '').gsub('.liquid', '').gsub(/^\//, '')

          next if %w(index 404).include?(fullpath)

          self.add_page(fullpath)
        end
      end

      protected

      def add_page(fullpath)
        page = context[:done][fullpath]

        return page if page # already added, so skip it

        template = File.read(File.join(theme_path, 'templates', "#{fullpath}.liquid")) rescue "Unable to find #{fullpath}.liquid"

        self.replace_images!(template)

        self.build_parent_template(template)

        parent = self.find_parent(fullpath)

        attributes = {
          :title        => fullpath.split('/').last.humanize,
          :slug         => fullpath.split('/').last,
          :parent       => parent,
          :raw_template => template
        }.merge(self.pages[fullpath] || {}).symbolize_keys

        # templatized ?
        if content_type_slug = attributes.delete(:content_type)
          fullpath.gsub!(/\/template$/, '/content_type_template')
          attributes.merge!({
            :templatized  => true,
            :content_type => site.content_types.where(:slug => content_type_slug).first
          })
        end

        page = site.pages.where(:fullpath => fullpath).first || site.pages.build

        page.attributes = attributes

        page.save!

        self.log "adding #{page.fullpath}"

        site.reload

        context[:done][fullpath] = page

        page
      end

      def build_parent_template(template)
        # just check if the template contains the extends keyword
        fullpath = template.scan(/\{% extends (\w+) %\}/).flatten.first

        if fullpath # inheritance detected
          fullpath.gsub!("'", '')

          return if fullpath == 'parent'

          self.add_page(fullpath)
        end
      end

      def find_parent(fullpath)
        segments = fullpath.split('/')

        return site.pages.index.first if segments.size == 1

        segments.pop

        parent_fullpath = segments.join('/').gsub(/^\//, '')

        # look for a local index page in db
        parent = site.pages.where(:fullpath => parent_fullpath).first

        parent || self.add_page(parent_fullpath)
      end

      def add_index_and_404
        %w(index 404).each_with_index do |slug, position|
          page = site.pages.where({ :slug => slug, :depth => 0 }).first

          page ||= sites.pages.build(:slug => slug, :parent => nil)

          template = File.read(File.join(theme_path, 'templates', "#{slug}.liquid"))

          self.replace_images!(template)

          page.attributes = { :raw_template => template }.merge(self.pages[slug] || {})

          page.position = position

          page.save! rescue nil # TODO better error handling

          site.reload

          context[:done][slug] = page
        end
      end

      def replace_images!(template)
        return if template.blank?

        template.gsub!(/\/samples\/(.*\.[a-zA-Z0-9]{3})/) do |match|
          name = $1

          collection = AssetCollection.find_or_create_internal(site)

          if asset = collection.assets.detect { |a| a.source_filename == name }
            asset.source.url
          else
            match
          end
        end
      end

      def pages
        @pages ||= self.retrieve_pages
      end

      def retrieve_pages
        pages = context[:database]['site']['pages']

        if pages.is_a?(Array) # ordered list of pages
          tmp = {}
          pages.each_with_index do |data, position|
            attributes = (data.values.first || {}).merge(:position => position)
            tmp[data.keys.first.to_s] = attributes
          end
          pages = tmp
        end

        pages
      end

    end
  end
end