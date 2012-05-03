use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'HTML-TagParser',
    VERSION_FROM        => 'lib/HTML/TagParser.pm',
    ABSTRACT_FROM       => 'lib/HTML/TagParser.pm',
    CONFIGURE_REQUIRES  =>  {
        'ExtUtils::MakeMaker' => '6.55',
    },
    BUILD_REQUIRES      =>  {
        'Test::More'    =>  '0',
    },
    PREREQ_PM           =>  {
        'Symbol'        =>  '0',
        'Carp'          =>  '0',
        'Encode'	=>  '0',
    },
    AUTHOR              =>  'Yusuke Kawasaki',
    LICENSE             =>  'perl',
);
