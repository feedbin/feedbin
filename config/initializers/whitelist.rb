Feedbin::Application.config.whitelist = HTML::Pipeline::SanitizationFilter::WHITELIST.clone
Feedbin::Application.config.whitelist[:attributes][:all] += ['id']
Feedbin::Application.config.whitelist[:elements] += ['figure', 'figcaption']
Feedbin::Application.config.whitelist[:protocols]['img']['src'] += ['data']