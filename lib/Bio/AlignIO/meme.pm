#line 1 "Bio/AlignIO/meme.pm"
# $id $
#
# BioPerl module for Bio::AlignIO::meme
#	based on the Bio::SeqIO modules
#       by Ewan Birney <birney@sanger.ac.uk>
#       and Lincoln Stein  <lstein@cshl.org>
#
#       and the SimpleAlign.pm module of Ewan Birney
#
# Copyright Benjamin Berman
#
# You may distribute this module under the same terms as perl itself
# _history

#line 61

# Let the code begin...

package Bio::AlignIO::meme;
use vars qw(@ISA);
use strict;

use Bio::AlignIO;
use Bio::LocatableSeq;

@ISA = qw(Bio::AlignIO);

# Constants
my $MEME_VERS_ERR = "MEME output file must be generated by version 3.0 or higher";
my $MEME_NO_HEADER_ERR = "MEME output file contains no header line (ex: MEME version 3.0)";
my $HTML_VERS_ERR = "MEME output file must be generated with the -text option";

#line 87

sub next_aln {
    my ($self) = @_;
    my $aln =  Bio::SimpleAlign->new(-source => 'meme');
    my $line;
    my $good_align_sec = 0;
    my $in_align_sec = 0;
    while (!$good_align_sec && defined($line = $self->_readline()))
      {
	if (!$in_align_sec)
	  {
	    # Check for the meme header
	    if ($line =~ /^\s*[Mm][Ee][Mm][Ee]\s+version\s+((?:\d+)?\.\d+)/)
	      {
		$self->{'meme_vers'} = $1;
		$self->throw($MEME_VERS_ERR) unless ($self->{'meme_vers'} >= 3.0);
		$self->{'seen_header'} = 1;
	      }

	    # Check if they've output the HTML version
	    if ($line =~ /\<[Tt][Ii][Tt][Ll][Ee]\>/)
	      {
		$self->throw($HTML_VERS_ERR);
	      }

	    # Check if we're going into an alignment section
	    if ($line =~ /sites sorted by position/)  # meme vers > 3.0
	      {
		$self->throw($MEME_NO_HEADER_ERR) unless ($self->{'seen_header'});
		$in_align_sec = 1;
	      }
	  }
	elsif ($line =~ /^\s*(\S+)\s+([+-])\s+(\d+)\s+(\S+)\s+([\.ACTGactg]*) ([ACTGactg]+) ([\.ACTGactg]*)/) 
	  {
	    # Got a sequence line
	    my $seq_name = $1;
	    my $strand = ($2 eq '+') ? 1 : -1;
	    my $start_pos = $3;
	    # my $p_val = $4;
	    # my $left_flank = uc($5);
	    my $central = uc($6);
	    # my $right_flank = uc($7);
	
	    # Info about the sequence
	    my $seq_res = $central;
	    my $seq_len = length($seq_res);

	    # Info about the flanking sequence
	    # my $left_len = length($left_flank);
	    # my $right_len = length($right_flank);
	    # my $start_len = ($strand > 0) ? $left_len : $right_len;
	    # my $end_len = ($strand > 0) ? $right_len : $left_len;

	    # Make the sequence.  Meme gives the start coordinate at the left
	    # hand side of the motif relative to the INPUT sequence.
	    my $start_coord = $start_pos;
	    my $end_coord = $start_coord + $seq_len - 1;
	    my $seq = new Bio::LocatableSeq('-seq'=>$seq_res,
					    '-id'=>$seq_name,
					    '-start'=>$start_coord,
					    '-end'=>$end_coord,
					    '-strand'=>$strand);

	    # Make a seq_feature out of the motif
	    $aln->add_seq($seq);
	  }
	elsif (($line =~ /^\-/) || ($line =~ /Sequence name/))
	  {
	    # These are acceptable things to be in the site section
	  }
	elsif ($line =~ /^\s*$/)
	  {
	    # This ends the site section
	    $in_align_sec = 0;
	    $good_align_sec = 1;
	  }
	else
	  {
	    $self->warn("Unrecognized format:\n$line");
	    return 0;
	  }
      }

    # Signal an error if we didn't find a header section
    $self->throw($MEME_NO_HEADER_ERR) unless ($self->{'seen_header'});

    return (($good_align_sec) ? $aln : 0);
}



#line 187

sub write_aln {
   my ($self,@aln) = @_;

   # Don't handle it yet.
   $self->throw("AlignIO::meme::write_aln not implemented");
   return 0;
}



# ----------------------------------------
# -   Private methods
# ----------------------------------------



sub _initialize {
  my($self,@args) = @_;

  # Call into our base version
  $self->SUPER::_initialize(@args);

  # Then initialize our data variables
  $self->{'seen_header'} = 0;
}


1;