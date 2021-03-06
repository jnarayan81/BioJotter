#line 1 "File/Find.pm"
package File::Find;
use 5.006;
use strict;
use warnings;
use warnings::register;
our $VERSION = '1.10';
require Exporter;
require Cwd;

#
# Modified to ensure sub-directory traversal order is not inverded by stack
# push and pops.  That is remains in the same order as in the directory file,
# or user pre-processing (EG:sorted).
#

#line 413

our @ISA = qw(Exporter);
our @EXPORT = qw(find finddepth);


use strict;
my $Is_VMS;
my $Is_MacOS;

require File::Basename;
require File::Spec;

# Should ideally be my() not our() but local() currently
# refuses to operate on lexicals

our %SLnkSeen;
our ($wanted_callback, $avoid_nlink, $bydepth, $no_chdir, $follow,
    $follow_skip, $full_check, $untaint, $untaint_skip, $untaint_pat,
    $pre_process, $post_process, $dangling_symlinks);

sub contract_name {
    my ($cdir,$fn) = @_;

    return substr($cdir,0,rindex($cdir,'/')) if $fn eq $File::Find::current_dir;

    $cdir = substr($cdir,0,rindex($cdir,'/')+1);

    $fn =~ s|^\./||;

    my $abs_name= $cdir . $fn;

    if (substr($fn,0,3) eq '../') {
       1 while $abs_name =~ s!/[^/]*/\.\./!/!;
    }

    return $abs_name;
}

# return the absolute name of a directory or file
sub contract_name_Mac {
    my ($cdir,$fn) = @_;
    my $abs_name;

    if ($fn =~ /^(:+)(.*)$/) { # valid pathname starting with a ':'

	my $colon_count = length ($1);
	if ($colon_count == 1) {
	    $abs_name = $cdir . $2;
	    return $abs_name;
	}
	else {
	    # need to move up the tree, but
	    # only if it's not a volume name
	    for (my $i=1; $i<$colon_count; $i++) {
		unless ($cdir =~ /^[^:]+:$/) { # volume name
		    $cdir =~ s/[^:]+:$//;
		}
		else {
		    return undef;
		}
	    }
	    $abs_name = $cdir . $2;
	    return $abs_name;
	}

    }
    else {

	# $fn may be a valid path to a directory or file or (dangling)
	# symlink, without a leading ':'
	if ( (-e $fn) || (-l $fn) ) {
	    if ($fn =~ /^[^:]+:/) { # a volume name like DataHD:*
		return $fn; # $fn is already an absolute path
	    }
	    else {
		$abs_name = $cdir . $fn;
		return $abs_name;
	    }
	}
	else { # argh!, $fn is not a valid directory/file
	     return undef;
	}
    }
}

sub PathCombine($$) {
    my ($Base,$Name) = @_;
    my $AbsName;

    if ($Is_MacOS) {
	# $Name is the resolved symlink (always a full path on MacOS),
	# i.e. there's no need to call contract_name_Mac()
	$AbsName = $Name;

	# (simple) check for recursion
	if ( ( $Base =~ /^$AbsName/) && (-d $AbsName) ) { # recursion
	    return undef;
	}
    }
    else {
	if (substr($Name,0,1) eq '/') {
	    $AbsName= $Name;
	}
	else {
	    $AbsName= contract_name($Base,$Name);
	}

	# (simple) check for recursion
	my $newlen= length($AbsName);
	if ($newlen <= length($Base)) {
	    if (($newlen == length($Base) || substr($Base,$newlen,1) eq '/')
		&& $AbsName eq substr($Base,0,$newlen))
	    {
		return undef;
	    }
	}
    }
    return $AbsName;
}

sub Follow_SymLink($) {
    my ($AbsName) = @_;

    my ($NewName,$DEV, $INO);
    ($DEV, $INO)= lstat $AbsName;

    while (-l _) {
	if ($SLnkSeen{$DEV, $INO}++) {
	    if ($follow_skip < 2) {
		die "$AbsName is encountered a second time";
	    }
	    else {
		return undef;
	    }
	}
	$NewName= PathCombine($AbsName, readlink($AbsName));
	unless(defined $NewName) {
	    if ($follow_skip < 2) {
		die "$AbsName is a recursive symbolic link";
	    }
	    else {
		return undef;
	    }
	}
	else {
	    $AbsName= $NewName;
	}
	($DEV, $INO) = lstat($AbsName);
	return undef unless defined $DEV;  #  dangling symbolic link
    }

    if ($full_check && defined $DEV && $SLnkSeen{$DEV, $INO}++) {
	if ( ($follow_skip < 1) || ((-d _) && ($follow_skip < 2)) ) {
	    die "$AbsName encountered a second time";
	}
	else {
	    return undef;
	}
    }

    return $AbsName;
}

our($dir, $name, $fullname, $prune);
sub _find_dir_symlnk($$$);
sub _find_dir($$$);

# check whether or not a scalar variable is tainted
# (code straight from the Camel, 3rd ed., page 561)
sub is_tainted_pp {
    my $arg = shift;
    my $nada = substr($arg, 0, 0); # zero-length
    local $@;
    eval { eval "# $nada" };
    return length($@) != 0;
}

sub _find_opt {
    my $wanted = shift;
    die "invalid top directory" unless defined $_[0];

    # This function must local()ize everything because callbacks may
    # call find() or finddepth()

    local %SLnkSeen;
    local ($wanted_callback, $avoid_nlink, $bydepth, $no_chdir, $follow,
	$follow_skip, $full_check, $untaint, $untaint_skip, $untaint_pat,
	$pre_process, $post_process, $dangling_symlinks);
    local($dir, $name, $fullname, $prune);
    local *_ = \my $a;

    my $cwd            = $wanted->{bydepth} ? Cwd::fastcwd() : Cwd::getcwd();
    my $cwd_untainted  = $cwd;
    my $check_t_cwd    = 1;
    $wanted_callback   = $wanted->{wanted};
    $bydepth           = $wanted->{bydepth};
    $pre_process       = $wanted->{preprocess};
    $post_process      = $wanted->{postprocess};
    $no_chdir          = $wanted->{no_chdir};
    $full_check        = $^O eq 'MSWin32' ? 0 : $wanted->{follow};
    $follow            = $^O eq 'MSWin32' ? 0 :
                             $full_check || $wanted->{follow_fast};
    $follow_skip       = $wanted->{follow_skip};
    $untaint           = $wanted->{untaint};
    $untaint_pat       = $wanted->{untaint_pattern};
    $untaint_skip      = $wanted->{untaint_skip};
    $dangling_symlinks = $wanted->{dangling_symlinks};

    # for compatibility reasons (find.pl, find2perl)
    local our ($topdir, $topdev, $topino, $topmode, $topnlink);

    # a symbolic link to a directory doesn't increase the link count
    $avoid_nlink      = $follow || $File::Find::dont_use_nlink;

    my ($abs_dir, $Is_Dir);

    Proc_Top_Item:
    foreach my $TOP (@_) {
	my $top_item = $TOP;

	($topdev,$topino,$topmode,$topnlink) = $follow ? stat $top_item : lstat $top_item;

	if ($Is_MacOS) {
	    $top_item = ":$top_item"
		if ( (-d _) && ( $top_item !~ /:/ ) );
	} elsif ($^O eq 'MSWin32') {
	    $top_item =~ s|/\z|| unless $top_item =~ m|\w:/$|;
	}
	else {
	    $top_item =~ s|/\z|| unless $top_item eq '/';
	}

	$Is_Dir= 0;

	if ($follow) {

	    if ($Is_MacOS) {
		$cwd = "$cwd:" unless ($cwd =~ /:$/); # for safety

		if ($top_item eq $File::Find::current_dir) {
		    $abs_dir = $cwd;
		}
		else {
		    $abs_dir = contract_name_Mac($cwd, $top_item);
		    unless (defined $abs_dir) {
			warnings::warnif "Can't determine absolute path for $top_item (No such file or directory)\n";
			next Proc_Top_Item;
		    }
		}

	    }
	    else {
		if (substr($top_item,0,1) eq '/') {
		    $abs_dir = $top_item;
		}
		elsif ($top_item eq $File::Find::current_dir) {
		    $abs_dir = $cwd;
		}
		else {  # care about any  ../
		    $abs_dir = contract_name("$cwd/",$top_item);
		}
	    }
	    $abs_dir= Follow_SymLink($abs_dir);
	    unless (defined $abs_dir) {
		if ($dangling_symlinks) {
		    if (ref $dangling_symlinks eq 'CODE') {
			$dangling_symlinks->($top_item, $cwd);
		    } else {
			warnings::warnif "$top_item is a dangling symbolic link\n";
		    }
		}
		next Proc_Top_Item;
	    }

	    if (-d _) {
		_find_dir_symlnk($wanted, $abs_dir, $top_item);
		$Is_Dir= 1;
	    }
	}
	else { # no follow
	    $topdir = $top_item;
	    unless (defined $topnlink) {
		warnings::warnif "Can't stat $top_item: $!\n";
		next Proc_Top_Item;
	    }
	    if (-d _) {
		$top_item =~ s/\.dir\z//i if $Is_VMS;
		_find_dir($wanted, $top_item, $topnlink);
		$Is_Dir= 1;
	    }
	    else {
		$abs_dir= $top_item;
	    }
	}

	unless ($Is_Dir) {
	    unless (($_,$dir) = File::Basename::fileparse($abs_dir)) {
		if ($Is_MacOS) {
		    ($dir,$_) = (':', $top_item); # $File::Find::dir, $_
		}
		else {
		    ($dir,$_) = ('./', $top_item);
		}
	    }

	    $abs_dir = $dir;
	    if (( $untaint ) && (is_tainted($dir) )) {
		( $abs_dir ) = $dir =~ m|$untaint_pat|;
		unless (defined $abs_dir) {
		    if ($untaint_skip == 0) {
			die "directory $dir is still tainted";
		    }
		    else {
			next Proc_Top_Item;
		    }
		}
	    }

	    unless ($no_chdir || chdir $abs_dir) {
		warnings::warnif "Couldn't chdir $abs_dir: $!\n";
		next Proc_Top_Item;
	    }

	    $name = $abs_dir . $_; # $File::Find::name
	    $_ = $name if $no_chdir;

	    { $wanted_callback->() }; # protect against wild "next"

	}

	unless ( $no_chdir ) {
	    if ( ($check_t_cwd) && (($untaint) && (is_tainted($cwd) )) ) {
		( $cwd_untainted ) = $cwd =~ m|$untaint_pat|;
		unless (defined $cwd_untainted) {
		    die "insecure cwd in find(depth)";
		}
		$check_t_cwd = 0;
	    }
	    unless (chdir $cwd_untainted) {
		die "Can't cd to $cwd: $!\n";
	    }
	}
    }
}

# API:
#  $wanted
#  $p_dir :  "parent directory"
#  $nlink :  what came back from the stat
# preconditions:
#  chdir (if not no_chdir) to dir

sub _find_dir($$$) {
    my ($wanted, $p_dir, $nlink) = @_;
    my ($CdLvl,$Level) = (0,0);
    my @Stack;
    my @filenames;
    my ($subcount,$sub_nlink);
    my $SE= [];
    my $dir_name= $p_dir;
    my $dir_pref;
    my $dir_rel = $File::Find::current_dir;
    my $tainted = 0;
    my $no_nlink;

    if ($Is_MacOS) {
	$dir_pref= ($p_dir =~ /:$/) ? $p_dir : "$p_dir:"; # preface
    } elsif ($^O eq 'MSWin32') {
	$dir_pref = ($p_dir =~ m|\w:/$| ? $p_dir : "$p_dir/" );
    }
    else {
	$dir_pref= ( $p_dir eq '/' ? '/' : "$p_dir/" );
    }

    local ($dir, $name, $prune, *DIR);

    unless ( $no_chdir || ($p_dir eq $File::Find::current_dir)) {
	my $udir = $p_dir;
	if (( $untaint ) && (is_tainted($p_dir) )) {
	    ( $udir ) = $p_dir =~ m|$untaint_pat|;
	    unless (defined $udir) {
		if ($untaint_skip == 0) {
		    die "directory $p_dir is still tainted";
		}
		else {
		    return;
		}
	    }
	}
	unless (chdir ($Is_VMS && $udir !~ /[\/\[<]+/ ? "./$udir" : $udir)) {
	    warnings::warnif "Can't cd to $udir: $!\n";
	    return;
	}
    }

    # push the starting directory
    push @Stack,[$CdLvl,$p_dir,$dir_rel,-1]  if  $bydepth;

    if ($Is_MacOS) {
	$p_dir = $dir_pref;  # ensure trailing ':'
    }

    while (defined $SE) {
	unless ($bydepth) {
	    $dir= $p_dir; # $File::Find::dir
	    $name= $dir_name; # $File::Find::name
	    $_= ($no_chdir ? $dir_name : $dir_rel ); # $_
	    # prune may happen here
	    $prune= 0;
	    { $wanted_callback->() };	# protect against wild "next"
	    next if $prune;
	}

	# change to that directory
	unless ($no_chdir || ($dir_rel eq $File::Find::current_dir)) {
	    my $udir= $dir_rel;
	    if ( ($untaint) && (($tainted) || ($tainted = is_tainted($dir_rel) )) ) {
		( $udir ) = $dir_rel =~ m|$untaint_pat|;
		unless (defined $udir) {
		    if ($untaint_skip == 0) {
			if ($Is_MacOS) {
			    die "directory ($p_dir) $dir_rel is still tainted";
			}
			else {
			    die "directory (" . ($p_dir ne '/' ? $p_dir : '') . "/) $dir_rel is still tainted";
			}
		    } else { # $untaint_skip == 1
			next;
		    }
		}
	    }
	    unless (chdir ($Is_VMS && $udir !~ /[\/\[<]+/ ? "./$udir" : $udir)) {
		if ($Is_MacOS) {
		    warnings::warnif "Can't cd to ($p_dir) $udir: $!\n";
		}
		else {
		    warnings::warnif "Can't cd to (" .
			($p_dir ne '/' ? $p_dir : '') . "/) $udir: $!\n";
		}
		next;
	    }
	    $CdLvl++;
	}

	if ($Is_MacOS) {
	    $dir_name = "$dir_name:" unless ($dir_name =~ /:$/);
	}

	$dir= $dir_name; # $File::Find::dir

	# Get the list of files in the current directory.
	unless (opendir DIR, ($no_chdir ? $dir_name : $File::Find::current_dir)) {
	    warnings::warnif "Can't opendir($dir_name): $!\n";
	    next;
	}
	@filenames = readdir DIR;
	closedir(DIR);
	@filenames = $pre_process->(@filenames) if $pre_process;
	push @Stack,[$CdLvl,$dir_name,"",-2]   if $post_process;

	# default: use whatever was specifid
        # (if $nlink >= 2, and $avoid_nlink == 0, this will switch back)
        $no_nlink = $avoid_nlink;
        # if dir has wrong nlink count, force switch to slower stat method
        $no_nlink = 1 if ($nlink < 2);

	if ($nlink == 2 && !$no_nlink) {
	    # This dir has no subdirectories.
	    for my $FN (@filenames) {
		next if $FN =~ $File::Find::skip_pattern;
		
		$name = $dir_pref . $FN; # $File::Find::name
		$_ = ($no_chdir ? $name : $FN); # $_
		{ $wanted_callback->() }; # protect against wild "next"
	    }

	}
	else {
	    # This dir has subdirectories.
	    $subcount = $nlink - 2;

	    # HACK: insert directories at this position. so as to preserve
	    # the user pre-processed ordering of files.
	    # EG: directory traversal is in user sorted order, not at random.
            my $stack_top = @Stack;

	    for my $FN (@filenames) {
		next if $FN =~ $File::Find::skip_pattern;
		if ($subcount > 0 || $no_nlink) {
		    # Seen all the subdirs?
		    # check for directoriness.
		    # stat is faster for a file in the current directory
		    $sub_nlink = (lstat ($no_chdir ? $dir_pref . $FN : $FN))[3];

		    if (-d _) {
			--$subcount;
			$FN =~ s/\.dir\z//i if $Is_VMS;
			# HACK: replace push to preserve dir traversal order
			#push @Stack,[$CdLvl,$dir_name,$FN,$sub_nlink];
			splice @Stack, $stack_top, 0,
			         [$CdLvl,$dir_name,$FN,$sub_nlink];
		    }
		    else {
			$name = $dir_pref . $FN; # $File::Find::name
			$_= ($no_chdir ? $name : $FN); # $_
			{ $wanted_callback->() }; # protect against wild "next"
		    }
		}
		else {
		    $name = $dir_pref . $FN; # $File::Find::name
		    $_= ($no_chdir ? $name : $FN); # $_
		    { $wanted_callback->() }; # protect against wild "next"
		}
	    }
	}
    }
    continue {
	while ( defined ($SE = pop @Stack) ) {
	    ($Level, $p_dir, $dir_rel, $nlink) = @$SE;
	    if ($CdLvl > $Level && !$no_chdir) {
		my $tmp;
		if ($Is_MacOS) {
		    $tmp = (':' x ($CdLvl-$Level)) . ':';
		}
		else {
		    $tmp = join('/',('..') x ($CdLvl-$Level));
		}
		die "Can't cd to $dir_name" . $tmp
		    unless chdir ($tmp);
		$CdLvl = $Level;
	    }

	    if ($Is_MacOS) {
		# $pdir always has a trailing ':', except for the starting dir,
		# where $dir_rel eq ':'
		$dir_name = "$p_dir$dir_rel";
		$dir_pref = "$dir_name:";
	    }
	    elsif ($^O eq 'MSWin32') {
		$dir_name = ($p_dir =~ m|\w:/$| ? "$p_dir$dir_rel" : "$p_dir/$dir_rel");
		$dir_pref = "$dir_name/";
	    }
	    else {
		$dir_name = ($p_dir eq '/' ? "/$dir_rel" : "$p_dir/$dir_rel");
		$dir_pref = "$dir_name/";
	    }

	    if ( $nlink == -2 ) {
		$name = $dir = $p_dir; # $File::Find::name / dir
                $_ = $File::Find::current_dir;
		$post_process->();		# End-of-directory processing
	    }
	    elsif ( $nlink < 0 ) {  # must be finddepth, report dirname now
		$name = $dir_name;
		if ($Is_MacOS) {
		    if ($dir_rel eq ':') { # must be the top dir, where we started
			$name =~ s|:$||; # $File::Find::name
			$p_dir = "$p_dir:" unless ($p_dir =~ /:$/);
		    }
		    $dir = $p_dir; # $File::Find::dir
		    $_ = ($no_chdir ? $name : $dir_rel); # $_
		}
		else {
		    if ( substr($name,-2) eq '/.' ) {
			substr($name, length($name) == 2 ? -1 : -2) = '';
		    }
		    $dir = $p_dir;
		    $_ = ($no_chdir ? $dir_name : $dir_rel );
		    if ( substr($_,-2) eq '/.' ) {
			substr($_, length($_) == 2 ? -1 : -2) = '';
		    }
		}
		{ $wanted_callback->() }; # protect against wild "next"
	     }
	     else {
		push @Stack,[$CdLvl,$p_dir,$dir_rel,-1]  if  $bydepth;
		last;
	    }
	}
    }
}


# API:
#  $wanted
#  $dir_loc : absolute location of a dir
#  $p_dir   : "parent directory"
# preconditions:
#  chdir (if not no_chdir) to dir

sub _find_dir_symlnk($$$) {
    my ($wanted, $dir_loc, $p_dir) = @_; # $dir_loc is the absolute directory
    my @Stack;
    my @filenames;
    my $new_loc;
    my $updir_loc = $dir_loc; # untainted parent directory
    my $SE = [];
    my $dir_name = $p_dir;
    my $dir_pref;
    my $loc_pref;
    my $dir_rel = $File::Find::current_dir;
    my $byd_flag; # flag for pending stack entry if $bydepth
    my $tainted = 0;
    my $ok = 1;

    if ($Is_MacOS) {
	$dir_pref = ($p_dir =~ /:$/) ? "$p_dir" : "$p_dir:";
	$loc_pref = ($dir_loc =~ /:$/) ? "$dir_loc" : "$dir_loc:";
    } else {
	$dir_pref = ( $p_dir   eq '/' ? '/' : "$p_dir/" );
	$loc_pref = ( $dir_loc eq '/' ? '/' : "$dir_loc/" );
    }

    local ($dir, $name, $fullname, $prune, *DIR);

    unless ($no_chdir) {
	# untaint the topdir
	if (( $untaint ) && (is_tainted($dir_loc) )) {
	    ( $updir_loc ) = $dir_loc =~ m|$untaint_pat|; # parent dir, now untainted
	     # once untainted, $updir_loc is pushed on the stack (as parent directory);
	    # hence, we don't need to untaint the parent directory every time we chdir
	    # to it later
	    unless (defined $updir_loc) {
		if ($untaint_skip == 0) {
		    die "directory $dir_loc is still tainted";
		}
		else {
		    return;
		}
	    }
	}
	$ok = chdir($updir_loc) unless ($p_dir eq $File::Find::current_dir);
	unless ($ok) {
	    warnings::warnif "Can't cd to $updir_loc: $!\n";
	    return;
	}
    }

    push @Stack,[$dir_loc,$updir_loc,$p_dir,$dir_rel,-1]  if  $bydepth;

    if ($Is_MacOS) {
	$p_dir = $dir_pref; # ensure trailing ':'
    }

    while (defined $SE) {

	unless ($bydepth) {
	    # change (back) to parent directory (always untainted)
	    unless ($no_chdir) {
		unless (chdir $updir_loc) {
		    warnings::warnif "Can't cd to $updir_loc: $!\n";
		    next;
		}
	    }
	    $dir= $p_dir; # $File::Find::dir
	    $name= $dir_name; # $File::Find::name
	    $_= ($no_chdir ? $dir_name : $dir_rel ); # $_
	    $fullname= $dir_loc; # $File::Find::fullname
	    # prune may happen here
	    $prune= 0;
	    lstat($_); # make sure  file tests with '_' work
	    { $wanted_callback->() }; # protect against wild "next"
	    next if $prune;
	}

	# change to that directory
	unless ($no_chdir || ($dir_rel eq $File::Find::current_dir)) {
	    $updir_loc = $dir_loc;
	    if ( ($untaint) && (($tainted) || ($tainted = is_tainted($dir_loc) )) ) {
		# untaint $dir_loc, what will be pushed on the stack as (untainted) parent dir
		( $updir_loc ) = $dir_loc =~ m|$untaint_pat|;
		unless (defined $updir_loc) {
		    if ($untaint_skip == 0) {
			die "directory $dir_loc is still tainted";
		    }
		    else {
			next;
		    }
		}
	    }
	    unless (chdir $updir_loc) {
		warnings::warnif "Can't cd to $updir_loc: $!\n";
		next;
	    }
	}

	if ($Is_MacOS) {
	    $dir_name = "$dir_name:" unless ($dir_name =~ /:$/);
	}

	$dir = $dir_name; # $File::Find::dir

	# Get the list of files in the current directory.
	unless (opendir DIR, ($no_chdir ? $dir_loc : $File::Find::current_dir)) {
	    warnings::warnif "Can't opendir($dir_loc): $!\n";
	    next;
	}
	@filenames = readdir DIR;
	closedir(DIR);

	for my $FN (@filenames) {
	    next if $FN =~ $File::Find::skip_pattern;

	    # follow symbolic links / do an lstat
	    $new_loc = Follow_SymLink($loc_pref.$FN);

	    # ignore if invalid symlink
	    unless (defined $new_loc) {
	        if ($dangling_symlinks) {
	            if (ref $dangling_symlinks eq 'CODE') {
	                $dangling_symlinks->($FN, $dir_pref);
	            } else {
	                warnings::warnif "$dir_pref$FN is a dangling symbolic link\n";
	            }
	        }

	        $fullname = undef;
	        $name = $dir_pref . $FN;
	        $_ = ($no_chdir ? $name : $FN);
	        { $wanted_callback->() };
	        next;
	    }

	    if (-d _) {
		push @Stack,[$new_loc,$updir_loc,$dir_name,$FN,1];
	    }
	    else {
		$fullname = $new_loc; # $File::Find::fullname
		$name = $dir_pref . $FN; # $File::Find::name
		$_ = ($no_chdir ? $name : $FN); # $_
		{ $wanted_callback->() }; # protect against wild "next"
	    }
	}

    }
    continue {
	while (defined($SE = pop @Stack)) {
	    ($dir_loc, $updir_loc, $p_dir, $dir_rel, $byd_flag) = @$SE;
	    if ($Is_MacOS) {
		# $p_dir always has a trailing ':', except for the starting dir,
		# where $dir_rel eq ':'
		$dir_name = "$p_dir$dir_rel";
		$dir_pref = "$dir_name:";
		$loc_pref = ($dir_loc =~ /:$/) ? $dir_loc : "$dir_loc:";
	    }
	    else {
		$dir_name = ($p_dir eq '/' ? "/$dir_rel" : "$p_dir/$dir_rel");
		$dir_pref = "$dir_name/";
		$loc_pref = "$dir_loc/";
	    }
	    if ( $byd_flag < 0 ) {  # must be finddepth, report dirname now
		unless ($no_chdir || ($dir_rel eq $File::Find::current_dir)) {
		    unless (chdir $updir_loc) { # $updir_loc (parent dir) is always untainted
			warnings::warnif "Can't cd to $updir_loc: $!\n";
			next;
		    }
		}
		$fullname = $dir_loc; # $File::Find::fullname
		$name = $dir_name; # $File::Find::name
		if ($Is_MacOS) {
		    if ($dir_rel eq ':') { # must be the top dir, where we started
			$name =~ s|:$||; # $File::Find::name
			$p_dir = "$p_dir:" unless ($p_dir =~ /:$/);
		    }
		    $dir = $p_dir; # $File::Find::dir
		     $_ = ($no_chdir ? $name : $dir_rel); # $_
		}
		else {
		    if ( substr($name,-2) eq '/.' ) {
			substr($name, length($name) == 2 ? -1 : -2) = ''; # $File::Find::name
		    }
		    $dir = $p_dir; # $File::Find::dir
		    $_ = ($no_chdir ? $dir_name : $dir_rel); # $_
		    if ( substr($_,-2) eq '/.' ) {
			substr($_, length($_) == 2 ? -1 : -2) = '';
		    }
		}

		lstat($_); # make sure file tests with '_' work
		{ $wanted_callback->() }; # protect against wild "next"
	    }
	    else {
		push @Stack,[$dir_loc, $updir_loc, $p_dir, $dir_rel,-1]  if  $bydepth;
		last;
	    }
	}
    }
}


sub wrap_wanted {
    my $wanted = shift;
    if ( ref($wanted) eq 'HASH' ) {
	if ( $wanted->{follow} || $wanted->{follow_fast}) {
	    $wanted->{follow_skip} = 1 unless defined $wanted->{follow_skip};
	}
	if ( $wanted->{untaint} ) {
	    $wanted->{untaint_pattern} = $File::Find::untaint_pattern
		unless defined $wanted->{untaint_pattern};
	    $wanted->{untaint_skip} = 0 unless defined $wanted->{untaint_skip};
	}
	return $wanted;
    }
    else {
	return { wanted => $wanted };
    }
}

sub find {
    my $wanted = shift;
    _find_opt(wrap_wanted($wanted), @_);
}

sub finddepth {
    my $wanted = wrap_wanted(shift);
    $wanted->{bydepth} = 1;
    _find_opt($wanted, @_);
}

# default
$File::Find::skip_pattern    = qr/^\.{1,2}\z/;
$File::Find::untaint_pattern = qr|^([-+@\w./]+)$|;

# These are hard-coded for now, but may move to hint files.
if ($^O eq 'VMS') {
    $Is_VMS = 1;
    $File::Find::dont_use_nlink  = 1;
}
elsif ($^O eq 'MacOS') {
    $Is_MacOS = 1;
    $File::Find::dont_use_nlink  = 1;
    $File::Find::skip_pattern    = qr/^Icon\015\z/;
    $File::Find::untaint_pattern = qr|^(.+)$|;
}

# this _should_ work properly on all platforms
# where File::Find can be expected to work
$File::Find::current_dir = File::Spec->curdir || '.';

$File::Find::dont_use_nlink = 1
    if $^O eq 'os2' || $^O eq 'dos' || $^O eq 'amigaos' || $^O eq 'MSWin32' ||
       $^O eq 'interix' || $^O eq 'cygwin' || $^O eq 'epoc' || $^O eq 'qnx' ||
	   $^O eq 'nto';

# Set dont_use_nlink in your hint file if your system's stat doesn't
# report the number of links in a directory as an indication
# of the number of files.
# See, e.g. hints/machten.sh for MachTen 2.2.
unless ($File::Find::dont_use_nlink) {
    require Config;
    $File::Find::dont_use_nlink = 1 if ($Config::Config{'dont_use_nlink'});
}

# We need a function that checks if a scalar is tainted. Either use the
# Scalar::Util module's tainted() function or our (slower) pure Perl
# fallback is_tainted_pp()
{
    local $@;
    eval { require Scalar::Util };
    *is_tainted = $@ ? \&is_tainted_pp : \&Scalar::Util::tainted;
}

1;
