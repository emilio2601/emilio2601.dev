module Jekyll
  class MarkdownExportGenerator < Generator
    safe true
    priority :low

    ALLOWED_FRONTMATTER = %w[
      title
      date
      author
      permalink
      categories
      description
      blurb
    ].freeze

    EXPLICIT_ONLY_FRONTMATTER = %w[
      excerpt
    ].freeze

    def generate(site)
      docs = []
      docs += site.posts.docs if site.posts.docs
      site.collections.each do |name, collection|
        docs += collection.docs if collection.docs
      end
      docs += site.pages

      docs.each do |post|
        next if post.data['no_markdown_export']

        post_url = post.url.to_s.chomp('/')

        # Handle root page
        if post_url.empty? || post_url == '/'
          dir = ''
          filename = 'index.md'
        else
          dir = File.dirname(post_url).sub(/^\//, '')
          filename = File.basename(post_url, '.*') + '.md'
        end

        content = build_export_content(post)

        export_path = File.join(site.source, '.markdown_exports', dir)
        FileUtils.mkdir_p(export_path)

        file_path = File.join(export_path, filename)
        File.write(file_path, content)

        site.static_files << MarkdownExportFile.new(site, export_path, '', filename, dir)
      end
    end

    def build_export_content(post)
      filtered = {}
      ALLOWED_FRONTMATTER.each do |key|
        if post.data.key?(key) && post.data[key] && post.data[key].to_s.strip != ''
          filtered[key] = post.data[key]
        end
      end

      source_frontmatter = extract_source_frontmatter(post.path)
      EXPLICIT_ONLY_FRONTMATTER.each do |key|
        if source_frontmatter.include?(key)
          filtered[key] = post.data[key] if post.data[key]
        end
      end

      raw_content = extract_raw_content(post.path)

      output = "---\n"
      filtered.each do |key, value|
        output += yaml_line(key, value)
      end
      output += "---\n\n"
      output += raw_content
      output
    end

    def extract_raw_content(path)
      return '' unless File.exist?(path)

      content = File.read(path)
      if content =~ /\A---\s*\n(.*?\n?)^---\s*\n/m
        content = $'
      end
      content
    end

    def extract_source_frontmatter(path)
      return [] unless File.exist?(path)

      content = File.read(path)
      if content =~ /\A---\s*\n(.*?\n?)^---\s*\n/m
        frontmatter_text = $1
        frontmatter_text.scan(/^(\w+):/).flatten
      else
        []
      end
    end

    def yaml_line(key, value)
      case value
      when Array
        if value.empty?
          "#{key}: []\n"
        else
          "#{key}:\n" + value.map { |v| "  - #{yaml_escape(v)}" }.join("\n") + "\n"
        end
      when Time, DateTime
        "#{key}: #{value.iso8601}\n"
      when Date
        "#{key}: #{value.to_s}\n"
      else
        "#{key}: #{yaml_escape(value.to_s)}\n"
      end
    end

    def yaml_escape(str)
      if str =~ /[:\#\[\]\{\}\,\&\*\?\|\-\<\>\=\!\%\@\`]/ || str =~ /\A[\s]/ || str =~ /[\s]\z/ || str.include?("\n")
        "\"#{str.gsub('"', '\\"').gsub("\n", "\\n")}\""
      else
        str
      end
    end
  end

  class MarkdownExportFile < StaticFile
    def initialize(site, base, dir, name, dest_dir)
      super(site, base, dir, name)
      @dest_dir = dest_dir
    end

    def destination(dest)
      File.join(dest, @dest_dir, @name)
    end
  end
end
