#line 1 "Bio/AlignIO/bl2seq.pm"
# $Id: bl2seq.pm,v 1.13.2.1 2003/06/18 12:19:52 jason Exp $
#
# BioPerl module for Bio::AlignIO::bl2seq

#	based on the Bio::SeqIO modules
#       by Ewan Birney <birney@sanger.ac.uk>
#       and Lincoln Stein  <lstein@cshl.org>
#
#	the Bio::Tools::BPlite modules by
#	Ian Korf (ikorf@sapiens.wustl.edu, http://sapiens.wustl.edu/~ikorf),
#	Lorenz Pollak (lorenz@ist.org, bioperl port)
#
#       and the SimpleAlign.pm module of Ewan Birney
#
# Copyright Peter Schattner
#
# You may distribute this module under the same terms as perl itself
# _history
# September 5, 2000
# POD documentation - main docs before the code

#line 94

# Let the code begin...

package Bio::AlignIO::bl2seq;
use vars qw(@ISA);
use strict;
# Object preamble - inherits from Bio::Root::Object

use Bio::AlignIO;
use Bio::Tools::BPbl2seq;

@ISA = qw(Bio::AlignIO);



sub _initialize {
    my ($self,@args) = @_;
    $self->SUPER::_initialize(@args);
    ($self->{'report_type'}) = $self->_rearrange([qw(REPORT_TYPE)],
						 @args);
    return 1;
}

#line 127

sub next_aln {
    my $self = shift;
    my ($start,$end,$name,$seqname,$seq,$seqchar);
    my $aln =  Bio::SimpleAlign->new(-source => 'bl2seq');
    $self->{'bl2seqobj'} =
    	$self->{'bl2seqobj'} || Bio::Tools::BPbl2seq->new(-fh => $self->_fh,
							  -report_type => $self->{'report_type'});
    my $bl2seqobj = $self->{'bl2seqobj'};
    my $hsp =   $bl2seqobj->next_feature;
    $seqchar = $hsp->querySeq;
    $start = $hsp->query->start;
    $end = $hsp->query->end;
    $seqname = 'Query-sequence';    # Query name not present in bl2seq report

#    unless ($seqchar && $start && $end  && $seqname) {return 0} ;	
    unless ($seqchar && $start && $end ) {return 0} ;	

    $seq = new Bio::LocatableSeq('-seq'=>$seqchar,
				 '-id'=>$seqname,
				 '-start'=>$start,
				 '-end'=>$end,
				 );

    $aln->add_seq($seq);

    $seqchar = $hsp->sbjctSeq;
    $start = $hsp->hit->start;
    $end = $hsp->hit->end;
    $seqname = $bl2seqobj->sbjctName;

    unless ($seqchar && $start && $end  && $seqname) {return 0} ;	

    $seq = new Bio::LocatableSeq('-seq'=>$seqchar,
				 '-id'=>$seqname,
				 '-start'=>$start,
				 '-end'=>$end,
				 );

    $aln->add_seq($seq);

    return $aln;

}
	

#line 183

sub write_aln {
    my ($self,@aln) = @_;

    $self->throw("Sorry: writing bl2seq output is not available! /n");
}

1;
