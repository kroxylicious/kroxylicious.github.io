module SamplePlugin
  class RedirectPageGenerator < Jekyll::Generator
    safe true

    def generate(site)
      config = site.data['redirects']
      latest_release = Version.parse(site.data['kroxylicious']['latestRelease'])
      releases = known_releases(site)
      config.each { |redirect_config|
        Jekyll.logger.info "generating redirects for #{redirect_config[0]}"
        redirect_config[1]['mappings'].each do |mapping|
          to_version = Version.parse(mapping['toVersion'] ||= latest_release)
          from_version = Version.parse(mapping['fromVersion'] ||= latest_release)
          versions = releases.select { |rel| rel.between?(from_version, to_version) }
          versions.each { |version|
            mapping['version'] = version
            site.pages << RedirectPage.new(site, redirect_config[0], redirect_config[1], mapping)
            if version == latest_release
              mapping['landing_version'] = "latest"
              site.pages << RedirectPage.new(site, redirect_config[0], redirect_config[1], mapping)
            end
          }
        end
        Jekyll.logger.info "Generated redirects #{redirect_config[0]}"
      }
    end

    private

    def known_releases(site)
      releases = []
      site.data['release'].sort.each do |release|
        releases << Version.parse(release[0])
      end
      releases.sort_by { |version| [version.major, version.minor, version.patch] }
    end
  end

  # Subclass of `Jekyll::Page` with custom method definitions.
  class RedirectPage < Jekyll::Page
    def initialize(site, group, redirect_config, mapping)

      @site = site # the current site instance.
      @base = site.source # path to the source directory.
      @dir = "/redirect/#{group}/#{mapping['landing_version'] || mapping['version']}/" # the directory the page will reside in.

      # All pages have the same filename, so define attributes straight away.
      @basename = mapping['name'] # filename without the extension.
      @ext = '.html' # the extension.
      @name = basename + ext # basically @basename + @ext.
      @layout = 'redirect.html'
      delay = redirect_config['delay'] ||= 1
      @data = {
        'target' => "#{redirect_config['baseUrl']}#{mapping['version']}#{mapping['path']}",
        'layout' => 'redirect',
        'delay' => "#{delay}",
      }

      Jekyll.logger.info "generated redirect from #{@dir}#{@basename} to #{data['target']}"
    end

    # Placeholders that are used in constructing page URL.
    def url_placeholders
      {
        :path => @dir,
        :category => @dir,
        :basename => basename,
        :output_ext => output_ext,
      }
    end
  end

  class Version
    include Comparable

    # @return [Integer]
    attr_reader :major

    # @return [Integer]
    attr_reader :minor

    # @return [Integer]
    attr_reader :patch

    def self.parse(version_string)
      if version_string.is_a? Version
        return version_string
      end
      if version_string.include? '_'
        parts = version_string.split('_').map { |x| x.to_i }
      elsif version_string.include? '.'
        parts = version_string.split('.').map { |x| x.to_i }
      else
        raise "Invalid version string: #{version_string}"
      end
      instance = allocate
      instance.send(:initialize, parts[0], parts[1], parts[2])
      instance
    end

    # @param [Integer] major
    # @param [Integer] minor
    # @param [Integer] patch
    def initialize(
      major,
      minor,
      patch
    )
      @major = major.to_i
      @minor = minor.to_i
      @patch = patch.to_i
    end

    # @return [String]
    def to_s
      "#{major}.#{minor}.#{patch}"
    end

    def ==(other)
      to_s == other.to_s
    end

    # See section #11 of https://semver.org/spec/v2.0.0.html
    # @return [Integer, nil] Returns -1, 0, or 1. or Nil if other is unsortable
    def <=>(other)
      if other.is_a? Version
        [major, minor, patch] <=> [other.major, other.minor, other.patch]
      else
        nil
      end
    end

    def between?(min, max)
      if (min.is_a? Version) && (max.is_a? Version)
        self >= min && self <= max
      end
    end
  end
end