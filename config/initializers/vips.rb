# Rails 8.1.3.1 (CVE-2026-66066) has Active Storage call Vips.block_untrusted(true)
# while booting, which disables libvips's unfuzzed loaders — including the
# ImageMagick delegate that reads ICO. Favicons are ICO more often than not, so
# FaviconCrawler::Image can't do its job with them blocked.
#
# There is no way to re-enable a single loader: Vips.block("VipsForeignLoadMagick",
# false) does not help, because libvips checks the untrusted flag separately from
# per-operation blocking. It's all or nothing.
Vips.block_untrusted(false) if defined?(Vips)

Vips.cache_set_max(0)