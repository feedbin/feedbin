# Be sure to restart your server when you modify this file.

# Add new mime types for use in respond_to blocks:
# Mime::Type.register "text/richtext", :rtf

# API v3 takes JSON Merge Patch (RFC 7396) bodies on PATCH, parsed like JSON.
Mime::Type.register "application/merge-patch+json", :merge_patch
ActionDispatch::Request.parameter_parsers[:merge_patch] = ActionDispatch::Request.parameter_parsers[:json]
