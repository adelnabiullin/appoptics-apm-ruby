Gem::Specification.new do |s|
    s.name = %q{oboe_fu}
    s.version = "0.2.0"
    s.date = %{2012-10-4}
    s.authors = ["Tracelytics, Inc."]
    s.email = %q{spiros@tracelytics.com}
    s.summary = %q{Oboe instrumentation for Ruby frameworks}
    s.homepage = %q{http://tracelytics.com}
    s.description = %q{Oboe instrumentation for Ruby frameworks}
    s.files = Dir.glob(File.join('**', '*.rb')) - ['init.rb']

    s.add_dependency('oboe', '>= 0.2.3')
end
