module Jekyll
  module CustomSortFilters
    def sort_by_semver_key(hash, direction = 'desc')
      unless hash.is_a?(Hash)
        raise ArgumentError, "Filter 'sort_by_semver_key' requires a Hash, but received a #{hash.class.name}."
      end

      sorted_array = hash.sort_by do |key, value|
        key_str = key.to_s

        normalized_str = key_str.gsub('.', '_')

        unless normalized_str.match?(/\A\d+_\d+_\d+\z/)
          raise ArgumentError, "Invalid semver key in 'sort_by_semver_key'. Expected '1.2.3' or '1_2_3', but found '#{key_str}'."
        end

        normalized_str.split('_').map { |part| part.rjust(5, '0') }.join('.')
      end

      # controlling this from the filter is convenient because 'sort_by_semver_key | reverse' doesn't work as expected
      if direction == 'desc'
        return sorted_array.reverse
      else
        return sorted_array
      end
    end
  end
end

Liquid::Template.register_filter(Jekyll::CustomSortFilters)
