#line 1 "Tk/Config.pm"
package Tk::Config;
require Exporter;
use base qw(Exporter);
$VERSION = '804.027';
$inc = '-I$(TKDIR)/pTk/mTk/xlib';
$define = '';
$xlib = '';
$xinc = '';
$gccopt = '';
$win_arch = 'MSWin32';
@EXPORT = qw($VERSION $inc $define $xlib $xinc $gccopt $win_arch);
1;
