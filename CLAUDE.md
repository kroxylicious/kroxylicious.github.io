This is the repo for the website associated with Kroxylicious. 
Kroxylicious is a Layer 7 proxy for the Kafka protocol.
The website uses Jekyll and is hosted on github.

The content in this repo is a mixture of two things:

* static markdown and HTML content, which doesn't change much between releases of the Kroxylicious software.
* version-specific documentation, where a new release of the Kroxylicious software produces new documentation about that version.

The version-specific content has index pages enumerating the downloads and documentation publications, which is templated using liquid templates.

When you make a change you should test it. 
The script `./run.sh` can be used to serve the site from a docker container. 
The preview site can then be accessed at `http://127.0.0.1:4000/`.

This GitHub repository is hosted on GitHub at `https://github.com/kroxylicious/kroxylicious.github.io`.
You can use the `gh` tool to interact with GitHub PRs.
Note that we do not use the website repo for issues. 
Instead, issues for the website are held in the main Kroxylicious repo `https://github.com/kroxylicious/kroxylicious`.
So if you need to interact with website issues you can use the `-R kroxylicious/kroxylicious` option, for example: `gh issue list -R kroxylicious/kroxylicious`.

When making commits, use the `Assisted-by:` trailer to attribute changes to AI tooling, rather than `Coauthored-by:`.

## Documentation Filtering System

The documentation index pages (`/documentation/` and `/documentation/{version}/`) use client-side filtering to help visitors find relevant guides.

### Structure

1. **Metadata**: Each version has a YAML file in `_data/documentation/` (e.g., `0_19_0.yaml`) containing guide metadata:
   - `title`, `description`, `path`: Basic guide information
   - `tags`: Array of category tags (e.g., `[filter, security]`)
   - `rank`: String to control sort order (e.g., '000', '010')

2. **Layout**: `_layouts/released-documentation.html` renders:
   - Filter buttons (All, Proxy, Filters, Kubernetes, Developer, Security, Governance)
   - Card grid with icons and tag badges
   - Cards include a `data-categories` attribute for JavaScript filtering

3. **Filtering**: `assets/scripts/doc-filter.js` provides vanilla JavaScript filtering
   - Progressive enhancement: works without JavaScript
   - Filters by matching tags in the `data-categories` attribute

4. **Styling**: `_sass/kroxylicious.scss` provides:
   - Filter button styles with active states
   - Category-specific border colours on cards
   - Icon and badge styling

### Current Filter Categories

- **proxy**: Core proxy functionality and configuration
- **filter**: Filter plugins (encryption, validation, multi-tenancy, OAuth, SASL, authorization)
- **kubernetes**: Kubernetes operator and deployment
- **developer**: Development tools, guides, and API documentation
- **security**: Security features (encryption, authentication, authorization)
- **governance**: Compliance and validation

### Adding New Categories

To add a new filter category:

1. Update YAML files in `_data/documentation/` for relevant versions
2. Add filter button in `_layouts/released-documentation.html` with Bootstrap Icon
3. Add icon mapping for card headers (same file)
4. Add category border style in `_sass/kroxylicious.scss`
5. No JavaScript changes needed (handles tags dynamically)

### Version Scope Convention

When updating documentation tags, typically update only recent versions (e.g., 0.16.0+) rather than all historical versions, to balance consistency with maintenance effort.
