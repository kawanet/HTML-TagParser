use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'HTML-TagParser',
    VERSION_FROM        => 'lib/HTML/TagParser.pm',
    PREREQ_PM           => {
        'Test::More'        => '0',
#       'URI::Fetch'        => '0',
    },
);
