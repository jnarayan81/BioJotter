#line 1 "URI/sips.pm"
package URI::sips;
require URI::sip;
@ISA=qw(URI::sip);

sub default_port { 5061 }

1;
