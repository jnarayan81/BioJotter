#line 1 "LWP/MediaTypes.pm"
package LWP::MediaTypes;

# $Id: MediaTypes.pm,v 1.32 2004/11/17 11:04:09 gisle Exp $

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(guess_media_type media_suffix);
@EXPORT_OK = qw(add_type add_encoding read_media_types);
$VERSION = sprintf("%d.%02d", q$Revision: 1.32 $ =~ /(\d+)\.(\d+)/);

require LWP::Debug;
use strict;

# note: These hashes will also be filled with the entries found in
# the 'media.types' file.

my %suffixType = (
    'txt'   => 'text/plain',
    'html'  => 'text/html',
    'gif'   => 'image/gif',
    'jpg'   => 'image/jpeg',
);

my %suffixExt = (
    'text/plain' => 'txt',
    'text/html'  => 'html',
    'image/gif'  => 'gif',
    'image/jpeg' => 'jpg',
);

#XXX: there should be some way to define this in the media.types files.
my %suffixEncoding = (
    'Z'   => 'compress',
    'gz'  => 'gzip',
    'hqx' => 'x-hqx',
    'uu'  => 'x-uuencode',
    'z'   => 'x-pack',
    'bz2' => 'x-bzip2',
);

read_media_types();



sub _dump {
    require Data::Dumper;
    Data::Dumper->new([\%suffixType, \%suffixExt, \%suffixEncoding],
		      [qw(*suffixType *suffixExt *suffixEncoding)])->Dump;
}


sub guess_media_type
{
    my($file, $header) = @_;
    return undef unless defined $file;

    my $fullname;
    if (ref($file)) {
	# assume URI object
	$file = $file->path;
	#XXX should handle non http:, file: or ftp: URIs differently
    }
    else {
	$fullname = $file;  # enable peek at actual file
    }

    my @encoding = ();
    my $ct = undef;
    for (file_exts($file)) {
	# first check this dot part as encoding spec
	if (exists $suffixEncoding{$_}) {
	    unshift(@encoding, $suffixEncoding{$_});
	    next;
	}
	if (exists $suffixEncoding{lc $_}) {
	    unshift(@encoding, $suffixEncoding{lc $_});
	    next;
	}

	# check content-type
	if (exists $suffixType{$_}) {
	    $ct = $suffixType{$_};
	    last;
	}
	if (exists $suffixType{lc $_}) {
	    $ct = $suffixType{lc $_};
	    last;
	}

	# don't know nothing about this dot part, bail out
	last;
    }
    unless (defined $ct) {
	# Take a look at the file
	if (defined $fullname) {
	    $ct = (-T $fullname) ? "text/plain" : "application/octet-stream";
	}
	else {
	    $ct = "application/octet-stream";
	}
    }

    if ($header) {
	$header->header('Content-Type' => $ct);
	$header->header('Content-Encoding' => \@encoding) if @encoding;
    }

    wantarray ? ($ct, @encoding) : $ct;
}


sub media_suffix {
    if (!wantarray && @_ == 1 && $_[0] !~ /\*/) {
	return $suffixExt{$_[0]};
    }
    my(@type) = @_;
    my(@suffix, $ext, $type);
    foreach (@type) {
	if (s/\*/.*/) {
	    while(($ext,$type) = each(%suffixType)) {
		push(@suffix, $ext) if $type =~ /^$_$/;
	    }
	}
	else {
	    while(($ext,$type) = each(%suffixType)) {
		push(@suffix, $ext) if $type eq $_;
	    }
	}
    }
    wantarray ? @suffix : $suffix[0];
}


sub file_exts 
{
    require File::Basename;
    my @parts = reverse split(/\./, File::Basename::basename($_[0]));
    pop(@parts);        # never consider first part
    @parts;
}


sub add_type 
{
    my($type, @exts) = @_;
    for my $ext (@exts) {
	$ext =~ s/^\.//;
	$suffixType{$ext} = $type;
    }
    $suffixExt{$type} = $exts[0] if @exts;
}


sub add_encoding
{
    my($type, @exts) = @_;
    for my $ext (@exts) {
	$ext =~ s/^\.//;
	$suffixEncoding{$ext} = $type;
    }
}


sub read_media_types 
{
    my(@files) = @_;

    local($/, $_) = ("\n", undef);  # ensure correct $INPUT_RECORD_SEPARATOR

    my @priv_files = ();
    if($^O eq "MacOS") {
	push(@priv_files, "$ENV{HOME}:media.types", "$ENV{HOME}:mime.types")
	    if defined $ENV{HOME};  # Some does not have a home (for instance Win32)
    }
    else {
	push(@priv_files, "$ENV{HOME}/.media.types", "$ENV{HOME}/.mime.types")
	    if defined $ENV{HOME};  # Some doesn't have a home (for instance Win32)
    }

    # Try to locate "media.types" file, and initialize %suffixType from it
    my $typefile;
    unless (@files) {
	if($^O eq "MacOS") {
	    @files = map {$_."LWP:media.types"} @INC;
	}
	else {
	    @files = map {"$_/LWP/media.types"} @INC;
	}
	push @files, @priv_files;
    }
    for $typefile (@files) {
	local(*TYPE);
	open(TYPE, $typefile) || next;
        LWP::Debug::debug("Reading media types from $typefile");
	while (<TYPE>) {
	    next if /^\s*#/; # comment line
	    next if /^\s*$/; # blank line
	    s/#.*//;         # remove end-of-line comments
	    my($type, @exts) = split(' ', $_);
	    add_type($type, @exts);
	}
	close(TYPE);
    }
}

1;


__END__

#line 300