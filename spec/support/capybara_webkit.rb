Capybara.javascript_driver = :webkit

Capybara::Webkit.configure do |config| # rubocop:disable Style/SymbolProc
  config.block_unknown_urls
end
