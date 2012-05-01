=head1 NAME

HTML::TagParser - Yet another HTML document parser with DOM-like methods

=head1 SYNOPSIS

Parse a HTML file and find its <title> element's value.

    my $html = HTML::TagParser->new( "index-j.html" );
    my $elem = $html->getElementsByTagName( "title" );
    print "<title>", $elem->innerText(), "</title>\n" if ref $elem;

Parse a HTML source and find its first <form action=""> attribute's value.

    my $src  = '<html><form action="hoge.cgi">...</form></html>';
    my $html = HTML::TagParser->new( $src );
    my $elem = $html->getElementsByTagName( "form" );
    print "<form action=\"", $elem->getAttribute("action"), "\">\n" if ref $elem;

Fetch a HTML file via HTTP, and display its all <a> elements and attributes.

    my $url  = 'http://www.kawa.net/xp/index-e.html';
    my $html = HTML::TagParser->new( $url );
    my @list = $html->getElementsByTagName( "a" );
    foreach my $elem ( @list ) {
        my $tagname = $elem->tagName;
        my $attr = $elem->attributes;
        my $text = $elem->innerText;
        print "<$tagname";
        foreach my $key ( sort keys %$attr ) {
            print " $key=\"$attr->{$key}\"";
        }
        if ( $text eq "" ) {
            print " />\n";
        } else {
            print ">$text</$tagname>\n";
        }
    }

=head1 DESCRIPTION

HTML::TagParser is a pure Perl module which parses HTML/XHTML files.
This module provides some methods like DOM interface.
This module is not strict about XHTML format
because many of HTML pages are not strict.
You know, many pages use <br> elemtents instead of <br/>
and have <p> elements which are not closed.

=head1 METHODS

=head2 $html = HTML::TagParser->new();

This method constructs an empty instance of the C<HTML::TagParser> class.

=head2 $html = HTML::TagParser->new( $url );

If new() is called with a URL,
this method fetches a HTML file from remote web server and parses it
and returns its instance.
L<URI::Fetch> module is required to fetch a file.

=head2 $html = HTML::TagParser->new( $file );

If new() is called with a filename,
this method parses a local HTML file and returns its instance 

=head2 $html = HTML::TagParser->new( "<html>...snip...</html>" );

If new() is called with a string of HTML source code,
this method parses it and returns its instance.

=head2 $html->fetch( $url, %param );

This method fetches a HTML file from remote web server and parse it.
The second argument is optional parameters for L<URI::Fetch> module.

=head2 $html->open( $file );

This method parses a local HTML file.

=head2 $html->parse( $source );

This method parses a string of HTML source code.

=head2 $elem = $html->getElementById( $id );

This method returns the element which id attribute is $id.

=head2 @elem = $html->getElementsByName( $name );

This method returns an array of elements which name attribute is $name.
On scalar context, the first element is only retruned.

=head2 @elem = $html->getElementsByTagName( $tagname );

This method returns an array of elements which tagName is $tagName.
On scalar context, the first element is only retruned.

=head2 @elem = $html->getElementsByClassName( $class );

This method returns an array of elements which className is $tagName.
On scalar context, the first element is only retruned.

=head2 @elem = $html->getElementsByAttribute( $attrname, $value );

This method returns an array of elements which $attrname attribute's value is $value.
On scalar context, the first element is only retruned.

=head1 HTML::TagParser::Element SUBCLASS

=head2 $tagname = $elem->tagName();

This method returns $elem's tagName.

=head2 $text = $elem->id();

This method returns $elem's id attribute.

=head2 $text = $elem->innerText();

This method returns $elem's innerText without tags.

=head2 $attr = $elem->attributes();

This method returns a hash of $elem's all attributes.

=head2 $value = $elem->getAttribute( $key );

This method returns the value of $elem's attributes which name is $key.

=head1 INTERNATIONALIZATION

This module natively understands the character encoding used in document 
by parsing its meta element.

    <meta http-equiv="Content-Type" content="text/html; charset=Shift_JIS">

The parsed document's encoding is converted 
as this class's fixed internal encoding "UTF-8".

=head1 AUTHOR

Yusuke Kawasaki, http://www.kawa.net/

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2006-2007 Yusuke Kawasaki. All rights reserved.
This program is free software; you can redistribute it and/or 
modify it under the same terms as Perl itself.

=cut
# ----------------------------------------------------------------

package HTML::TagParser;
use strict;
use Symbol;
use Carp;

use vars qw( $VERSION );
$VERSION = "0.16";

my $J2E        = {qw( jis ISO-2022-JP sjis Shift_JIS euc EUC-JP ucs2 UCS2 )};
my $E2J        = { map { lc($_) } reverse %$J2E };
my $SEC_OF_DAY = 60 * 60 * 24;

sub new {
    my $package = shift;
    my $src     = shift;
    my $self    = {};
    bless $self, $package;
    return $self unless defined $src;

    if ( $src =~ m#^https?://\w# ) {
        $self->fetch( $src, @_ );
    }
    elsif ( $src !~ m#[\<\>\|]# && -f $src ) {
        $self->open($src);
    }
    elsif ( $src =~ /<.*>/ ) {
        $self->parse($src);
    }

    $self;
}

sub fetch {
    my $self = shift;
    my $url  = shift;
    if ( !defined $URI::Fetch::VERSION ) {
        local $@;
        eval { require URI::Fetch; };
        Carp::croak "URI::Fetch is required: $url" if $@;
    }
    my $res = URI::Fetch->fetch( $url, @_ );
    Carp::croak "URI::Fetch failed: $url" unless ref $res;
    return if $res->is_error();
    $self->{modified} = $res->last_modified();
    my $text = $res->content();
    $self->parse( \$text );
}

sub open {
    my $self = shift;
    my $file = shift;
    my $text = HTML::TagParser::Util::read_text_file($file);
    return unless defined $text;
    my $epoch = ( time() - ( -M $file ) * $SEC_OF_DAY );
    $epoch -= $epoch % 60;
    $self->{modified} = $epoch;
    $self->parse( \$text );
}

sub parse {
    my $self   = shift;
    my $text   = shift;
    my $txtref = ref $text ? $text : \$text;

    my $charset = HTML::TagParser::Util::find_meta_charset($txtref);
    if ( !$charset && $$txtref =~ /[^\000-\177]/ ) {
        HTML::TagParser::Util::load_jcode();
        my ($jc) = Jcode::getcode($txtref) if $Jcode::VERSION;
        $charset = $J2E->{$jc} if $J2E->{$jc};
    }
    $self->{charset} ||= $charset;
    if ($charset) {
        HTML::TagParser::Util::encode_from_to( $txtref, $charset, "utf-8" );
    }
    my $flat = HTML::TagParser::Util::html_to_flat($txtref);
    Carp::croak "Null HTML document." unless scalar @$flat;
    $self->{flat} = $flat;
    scalar @$flat;
}

sub getElementsByTagName {
    my $self    = shift;
    my $tagname = lc(shift);

    my $flat = $self->{flat};
    my $out = [];
    for( my $i = 0 ; $i <= $#$flat ; $i++ ) {
        next if ( $flat->[$i]->[001] ne $tagname );
        next if $flat->[$i]->[000];                 # close
        my $elem = HTML::TagParser::Element->new( $flat, $i );
        return $elem unless wantarray;
        push( @$out, $elem );
    }
    return unless wantarray;
    @$out;
}

sub getElementsByAttribute {
    my $self = shift;
    my $key  = lc(shift);
    my $val  = shift;

    my $flat = $self->{flat};
    my $out  = [];
    for ( my $i = 0 ; $i <= $#$flat ; $i++ ) {
        next if $flat->[$i]->[000];    # close
        my $elem = HTML::TagParser::Element->new( $flat, $i );
        my $attr = $elem->attributes();
        next unless exists $attr->{$key};
        next if ( $attr->{$key} ne $val );
        return $elem unless wantarray;
        push( @$out, $elem );
    }
    return unless wantarray;
    @$out;
}

sub getElementsByClassName {
    my $self  = shift;
    my $class = shift;
    return $self->getElementsByAttribute( "class", $class );
}

sub getElementsByName {
    my $self = shift;
    my $name = shift;
    return $self->getElementsByAttribute( "name", $name );
}

sub getElementById {
    my $self = shift;
    my $id   = shift;
    return scalar $self->getElementsByAttribute( "id", $id );
}

sub modified {
    $_[0]->{modified};
}

# ----------------------------------------------------------------

package HTML::TagParser::Element;
use strict;

sub new {
    my $package = shift;
    my $self    = [@_];
    bless $self, $package;
    $self;
}

sub tagName {
    my $self = shift;
    my ( $flat, $cur ) = @$self;
    return $flat->[$cur]->[001];
}

sub id {
    my $self = shift;
    $self->getAttribute("id");
}

sub getAttribute {
    my $self = shift;
    my $name = lc(shift);
    my $attr = $self->attributes();
    return unless exists $attr->{$name};
    $attr->{$name};
}

sub innerText {
    my $self = shift;
    my ( $flat, $cur ) = @$self;
    my $elem = $flat->[$cur];
    return $elem->[005] if defined $elem->[005];    # cache
    return if $elem->[000];                         # </xxx>
    return if ( defined $elem->[002] && $elem->[002] =~ m#/$# ); # <xxx/>

    my $tagname = $elem->[001];
    my $list    = [];
    for ( ; $cur < $#$flat ; $cur++ ) {
        push( @$list, $flat->[$cur]->[003] );
        last if ( $flat->[ $cur + 1 ]->[001] eq $tagname );
    }
    my $text = join( "", grep { $_ ne "" } @$list );
    $text =~ s/^\s+//s;
    $text =~ s/\s+$//s;
#   $text = "" if ( $cur == $#$flat );              # end of source
    $elem->[005] = HTML::TagParser::Util::xml_unescape( $text );
}

sub attributes {
    my $self = shift;
    my ( $flat, $cur ) = @$self;
    my $elem = $flat->[$cur];
    return $elem->[004] if ref $elem->[004];    # cache
    return unless defined $elem->[002];
    my $attr = {};
    while ( $elem->[002] =~ m{
        ([^\s\=\"\']+)(\s*=\s*(?:(")(.*?)"|(')(.*?)'|([^'"\s=]+)['"]*))?
    }sgx ) {
        my $key  = $1;
        my $test = $2;
        my $val  = ( $3 ? $4 : ( $5 ? $6 : $7 ));
        my $lckey = lc($key);
        if ($test) {
            $key =~ tr/A-Z/a-z/;
            $val = HTML::TagParser::Util::xml_unescape( $val );
            $attr->{$lckey} = $val;
        }
        else {
            $attr->{$lckey} = $key;
        }
    }
    $elem->[004] = $attr;    # cache
    $attr;
}

# ----------------------------------------------------------------

package HTML::TagParser::Util;
use strict;

sub xml_unescape {
    my $str = shift;
    $str =~ s/&quot;/"/g;
    $str =~ s/&lt;/</g;
    $str =~ s/&gt;/>/g;
    $str =~ s/&amp;/&/g;
    $str;
}

sub read_text_file {
    my $file = shift;
    my $fh   = Symbol::gensym();
    open( $fh, $file ) or Carp::croak "$! - $file\n";
    local $/ = undef;
    my $text = <$fh>;
    close($fh);
    $text;
}

sub html_to_flat {
    my $txtref  = shift;    # reference
    my $flat = [];
    pos($$txtref) = undef;  # reset matching position
    while ( $$txtref =~ m{
        (?:[^<]*) < (?:
            ( / )? ( [^/!<>\s"'=]+ )
            ( (?:"[^"]*"|'[^']*'|[^"'<>])+ )?
        |   
            (!-- .*? -- | ![^\-] .*? )
        ) > ([^<]*)
    }sxg ) {
        #  [000]  $1  close
        #  [001]  $2  tagName
        #  [002]  $3  attributes
        #         $4  comment element
        #  [003]  $5  content
        next if defined $4;
        my $array = [ $1, $2, $3, $5 ];
        $array->[001] =~ tr/A-Z/a-z/;
        #  $array->[003] =~ s/^\s+//s;
        #  $array->[003] =~ s/\s+$//s;
        push( @$flat, $array );
    }
    $flat;
}

sub find_meta_charset {
    my $txtref = shift;    # reference
    while ( $$txtref =~ m{
        <meta \s ((?: [^>]+\s )? http-equiv=['"]?Content-Type [^>]+ ) >
    }sxgi ) {
        my $args = $1;
        return $1 if ( $args =~ m# charset=['"]?([^'"\s/]+) #sxgi );
    }
    undef;
}

sub encode_from_to {
    my ( $txtref, $from, $to ) = @_;
    return     if ( $from     eq "" );
    return     if ( $to       eq "" );
    return $to if ( uc($from) eq uc($to) );
    &load_encode() if ( $] > 5.008 );
    if ( defined $Encode::VERSION ) {
        # 2006/11/01 FB_XMLCREF -> XMLCREF see [Jcode5 802]
        Encode::from_to( $$txtref, $from, $to, Encode::XMLCREF() );
    }
    elsif ( (  uc($from) eq "ISO-8859-1"
            || uc($from) eq "US-ASCII"
            || uc($from) eq "LATIN-1" ) && uc($to) eq "UTF-8" ) {
        &latin1_to_utf8($txtref);
    }
    else {
        my $jfrom = &get_jcode_name($from);
        my $jto   = &get_jcode_name($to);
        return $to if ( uc($jfrom) eq uc($jto) );
        if ( $jfrom && $jto ) {
            &load_jcode();
            if ( defined $Jcode::VERSION ) {
                Jcode::convert( $txtref, $jto, $jfrom );
            }
            else {
                Carp::croak "Jcode.pm is required: $from to $to";
            }
        }
        else {
            Carp::croak "Encode.pm is required: $from to $to";
        }
    }
    $to;
}

sub latin1_to_utf8 {
    my $txtref = shift;
    $$txtref =~ s{
        ([\x80-\xFF])
    }{
        pack( "C2" => 0xC0|(ord($1)>>6),0x80|(ord($1)&0x3F) )
    }exg;
}

sub load_jcode {
    return if defined $Jcode::VERSION;
    local $@;
    eval { require Jcode; };
}

sub load_encode {
    return if defined $Encode::VERSION;
    local $@;
    eval { require Encode; };
}

sub get_jcode_name {
    my $src = shift;
    my $dst;
    if ( $src =~ /^utf-?8$/i ) {
        $dst = "utf8";
    }
    elsif ( $src =~ /^euc.*jp$/i ) {
        $dst = "euc";
    }
    elsif ( $src =~ /^(shift.*jis|cp932|windows-31j)$/i ) {
        $dst = "sjis";
    }
    elsif ( $src =~ /^iso-2022-jp/ ) {
        $dst = "jis";
    }
    $dst;
}

# ----------------------------------------------------------------
1;
# ----------------------------------------------------------------
