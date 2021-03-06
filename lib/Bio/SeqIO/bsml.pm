#line 1 "Bio/SeqIO/bsml.pm"
#
# BioPerl module for Bio::SeqIO::bsml
#
# Cared for by Charles Tilford (tilfordc@bms.com)
# Copyright (C) Charles Tilford 2001
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
# 
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
# 
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
# Also at:   http://www.gnu.org/copyleft/lesser.html


# Much of the basic documentation in this module has been
# cut-and-pasted from the embl.pm (Ewan Birney) SeqIO module.


#line 133

package Bio::SeqIO::bsml;
use vars qw(@ISA);
use strict;

use Bio::SeqIO;
use Bio::SeqFeature::Generic;
use Bio::Species;
use XML::DOM;
use Bio::Seq::SeqFactory;
use Bio::Annotation::Collection;
use Bio::Annotation::Comment;
use Bio::Annotation::Reference;
use Bio::Annotation::DBLink;

@ISA = qw(Bio::SeqIO);

my $idcounter = {};  # Used to generate unique id values
my $nvtoken = ": ";  # The token used if a name/value pair has to be stuffed
                     # into a single line

#line 157

# LS: this seems to get overwritten on line 1317, generating a redefinition error.  Dead code?
# CAT: This was inappropriately added in revision 1.10 - I added the check for existance of a sequence factory to the actual _initialize
# sub _initialize {
#   my($self,@args) = @_;
#   $self->SUPER::_initialize(@args);  
#   if( ! defined $self->sequence_factory ) {
#       $self->sequence_factory(new Bio::Seq::SeqFactory(-verbose => $self->verbose(), -type => 'Bio::Seq::RichSeq'));
#   }
# }

#line 177

sub next_seq {
    my $self = shift;
    my ($desc);
    my $bioSeq = $self->sequence_factory->create(-verbose =>$self->verbose());
    
    unless (exists $self->{'domtree'}) {
	$self->throw("A BSML document has not yet been parsed.");
	return undef;
    }
    my $dom = $self->{'domtree'};
    my $seqElements = $dom->getElementsByTagName ("Sequence");
    if ($self->{'current_node'} == $seqElements->getLength ) {
	# There are no more <Sequence>s to process
	return undef;
    }
    my $xmlSeq = $seqElements->item($self->{'current_node'});
    
    # Assume that title attribute contains the best display id
    if (my $val = $xmlSeq->getAttribute( "title")) {
       $bioSeq->display_id($val);
   }
    
    # Set the molecule type
    if (my $val = $xmlSeq->getAttribute( "molecule" )) {
	my %mol = ('dna' => 'DNA', 'rna' => 'RNA', 'aa' => 'protein');
	$bioSeq->molecule($mol{ lc($val) });
    }
    
    # Set the accession number
    if (my $val = $xmlSeq->getAttribute( "ic-acckey" )) {
	$bioSeq->accession_number($val);
    }
    
    # Get the sequence data for the element
    if (my $seqData = &FIRSTDATA($xmlSeq->getElementsByTagName("Seq-data")
				 ->item(0) ) ) {
	# Sequence data exists, transfer to the Seq object
	# Remove white space and CRs (not neccesary?)
	$seqData =~ s/[\s\n\r]//g;
	$bioSeq->seq($seqData);
    } elsif (my $import = $xmlSeq->getElementsByTagName("Seq-dataimport")
	     ->item(0) )  {
#>>>>  # What about <Seq-data-import> ??
	
    } elsif (my $val = $xmlSeq->getAttribute("length"))  {
	# No sequence defined, set the length directly
	
#>>>>   # This does not appear to work - length is apparently calculated
	# from the sequence. How to make a "virtual" sequence??? Such
	# creatures are common in BSML...
	$bioSeq->length($val);
    }
   
    my $species = Bio::Species->new();
    my @classification = ();
    
    # Peruse the generic <Attributes> - those that are direct children of
    # the <Sequence> or the <Feature-tables> element
    # Sticky wicket here - data not controlled by schema, could be anything
    my @seqDesc = ();
    my %specs = ('common_name' => 'y', 
		 'genus' => 'y', 
		 'species' => 'y', 
		 'sub_species' => 'y', );
    my %seqMap = (
		  'add_date' => [ 'date' ],
		  'keywords' => [ 'keyword', ],
		  'seq_version' => [ 'version' ],
		  'division' => [ 'division' ],
		  'add_secondary_accession' => ['accession'],
		  'pid' => ['pid'],
		  'primary_id' => [ 'primary.id', 'primary_id' ],
		  );
    my $floppies = &GETFLOPPIES($xmlSeq);
    foreach my $attr (@{$floppies}) {
	# Don't want to get attributes from <Feature> or <Table> elements yet
	my $parent = $attr->getParentNode->getNodeName;
	next unless($parent eq "Sequence" || $parent eq "Feature-tables");
	
	my ($name, $content) = &FLOPPYVALS($attr);
	$name = lc($name);
	if (exists $specs{$name}) { # It looks like part of species...
	    $species->$name($content);
	    next;
	}
	my $value = "";
	# Cycle through the Seq methods:
	foreach my $method (keys %seqMap) {
	    # Cycle through potential matching attributes:
	    foreach my $match (@{$seqMap{$method}}) {
		# If the <Attribute> name matches one of the keys,
		# set $value, unless it has already been set
		$value ||= $content if ($name =~ /$match/i);
	    }
	    if ($value ne "") {
		$bioSeq->$method($value);
		last;
	    }
	}
	next if ($value ne "");

	if ($name =~ /^species$/i) {   # Uh, it's the species designation?
	    if ($content =~ / /) {
		# Assume that a full species name has been provided
		# This will screw up if the last word is the subspecies...
		my @break = split " ", $content;
		@classification = reverse @break;
	    } else {
		$classification[0] = $content;
	    }
	    next;
	}
	if ($name =~ /sub[_ ]?species/i) {  # Should be the subspecies...
	    $species->sub_species( $content );
	    next;
	}
	if ($name =~ /classification/i) {  # Should be species classification
	    # We will assume that there are spaces separating the terms:
	    my @bits = split " ", $content;
	    # Now make sure there is not other cruft as well (eg semi-colons)
	    for my $i (0..$#bits) {
		$bits[$i] =~ /(\w+)/;
		$bits[$i] = $1;
	    }
	    $species->classification( @bits );
	    next;
	}
	if ($name =~ /comment/) {
	    my $com = Bio::Annotation::Comment->new('-text' => $content);
	  #  $bioSeq->annotation->add_Comment($com);
	    $bioSeq->annotation->add_Annotation('comment', $com);
	    next;
	}
	# Description line - collect all descriptions for later assembly
	if ($name =~ /descr/) {
	    push @seqDesc, $content;
	    next;
	}
	# Ok, we have no idea what this attribute is. Dump to SimpleValue
	my $simp = Bio::Annotation::SimpleValue->new( -value => $content);
	$bioSeq->annotation->add_Annotation($name, $simp);
    }
    unless ($#seqDesc < 0) {
	$bioSeq->desc( join "; ", @seqDesc);
    }

#>>>>  This should be modified so that any IDREF associated with the
    # <Reference> is then used to associate the reference with the
    # appropriate Feature
    
    # Extract out <Reference>s associated with the sequence
    my @refs;
    my %tags = (
		-title => "RefTitle",
		-authors => "RefAuthors",
		-location => "RefJournal",
		);
    foreach my $ref ( $xmlSeq->getElementsByTagName ("Reference") ) {
	my %refVals;
	foreach my $tag (keys %tags) {
	    my $rt = &FIRSTDATA($ref->getElementsByTagName($tags{$tag})
				->item(0));
	    $rt =~ s/^[\s\r\n]+//;  # Kill leading space
	    $rt =~ s/[\s\r\n]+$//;  # Kill trailing space
	    $rt =~ s/[\s\r\n]+/ /;  # Collapse internal space runs
	    $refVals{$tag} = $rt;
	}
	my $reference = Bio::Annotation::Reference->new( %refVals );
	
	# Pull out any <Reference> information hidden in <Attributes>
	my %refMap = (
		      comment => [ 'comment', 'remark' ],
		      medline => [ 'medline', ],
		      pubmed => [ 'pubmed' ],
		      start => [ 'start', 'begin' ],
		      end => [ 'stop', 'end' ],
		      );
	my @refCom = ();
	my $floppies = &GETFLOPPIES($ref);
	foreach my $attr (@{$floppies}) {
	    my ($name, $content) = &FLOPPYVALS($attr);
	    my $value = "";
	    # Cycle through the Seq methods:
	    foreach my $method (keys %refMap) {
		# Cycle through potential matching attributes:
		foreach my $match (@{$refMap{$method}}) {
		    # If the <Attribute> name matches one of the keys,
		    # set $value, unless it has already been set
		    $value ||= $content if ($name =~ /$match/i);
		}
		if ($value ne "") {
		    my $str = '$reference->' . $method . "($value)";
		    eval($str);
		    next;
		}
	    }
	    next if ($value ne "");
	    # Don't know what the <Attribute> is, dump it to comments:
	    push @refCom, $name . $nvtoken . $content;
	}
	unless ($#refCom < 0) {
	    # Random stuff was found, tack it to the comment field
	    my $exist = $reference->comment;
	    $exist .= join ", ", @refCom;
	    $reference->comment($exist);
	}
	push @refs, $reference;
    }
    $bioSeq->annotation->add_Annotation('reference'=>$_) foreach @refs;
    
    # Extract the <Feature>s for this <Sequence>
    foreach my $feat ( $xmlSeq->getElementsByTagName("Feature") ) {
	$bioSeq->add_SeqFeature( $self->_parse_bsml_feature($feat) );
    }
    
    $species->classification( @classification );
    $bioSeq->species( $species );
    
# $seq->annotation->add_DBLink(@links);    ->
    
    $self->{'current_node'}++;
    return $bioSeq;
}
#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - 
# Get all the <Attribute> and <Qualifier> children for an object, and
# return them as an array reference
# ('floppy' since these elements have poor/no schema control)
sub GETFLOPPIES {
    my $obj = shift;
    
    my @floppies;
    my $attributes = $obj->getElementsByTagName ("Attribute");
    for (my $i = 0; $i < $attributes->getLength; $i++) {
	push @floppies, $attributes->item($i);
    }
    my $qualifiers = $obj->getElementsByTagName ("Qualifier");
    for (my $i = 0; $i < $qualifiers->getLength; $i++) {
	push @floppies, $qualifiers->item($i);
    }
    return \@floppies;
}
#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - 
# Given a DOM <Attribute> or <Qualifier> object, return the [name, value] pair
sub FLOPPYVALS {
    my $obj = shift;

    my ($name, $value);
    if      ($obj->getNodeName eq "Attribute") {
	$name  = $obj->getAttribute('name');
	$value = $obj->getAttribute('content');
    } elsif ($obj->getNodeName eq "Qualifier") {
	# Wheras <Attribute>s require both 'name' and 'content' attributes,
	# <Qualifier>s can technically have either blank (and sometimes do)
	my $n =  $obj->getAttribute('value-type');
	$name = $n if ($n ne "");
	my $v =  $obj->getAttribute('value');
	$value = $v if ($v ne "");
    }
    return ($name, $value);
}
#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - 
# Returns the value of the first TEXT_NODE encountered below an element
# Rational - avoid grabbing a comment rather than the PCDATA. Not foolproof...
sub FIRSTDATA {
    my $element = shift;
    return undef unless ($element);

    my $hopefuls = $element->getChildNodes;
    my $data;
    for (my $i = 0; $i < $hopefuls->getLength; $i++) {
	if ($hopefuls->item($i)->getNodeType ==
	  XML::DOM::Node::TEXT_NODE() ) {
	    $data = $hopefuls->item($i)->getNodeValue;
	    last;
	}
    }
    return $data;
}
#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - 
# Just collapses whitespace runs in a string
sub STRIP {
    my $string = shift;
    $string =~ s/[\s\r\n]+/ /g;
    return $string;
}

#line 523

sub to_bsml {
    my $self = shift;
    my $args = $self->_parseparams( -close => 1,
				    -return => 'xml',
				    @_);
    $args->{NODISP} ||= $args->{NODISPLAY};
    my $seqref = $args->{SEQ};
    $seqref = (ref($seqref) eq 'ARRAY') ? $seqref : [ $seqref ];

    #############################
    # Basic BSML XML Components #
    #############################
    
    my $xml;
    my ($bsmlElem, $defsElem, $seqsElem, $dispElem);
    if ($args->{XMLDOC}) {
	# The user has provided an existing XML DOM object
	$xml = $args->{XMLDOC};
	unless ($xml->isa("XML::DOM::Document")) {
	    die ('SeqIO::bsml.pm error:\n'.
		 'When calling ->to_bsml( { xmldoc => $myDoc }), $myDoc \n' .
		 'should be an XML::DOM::Document object, or an object that\n'.
		 'inherits from that class (like BsmlHelper.pm)');
	}
    } else {
	# The user has not provided a new document, make one from scratch
	$xml = XML::DOM::Document->new();
	$xml->setXMLDecl( $xml->createXMLDecl("1.0") );
	my $url = "http://www.labbook.com/dtd/bsml2_2.dtd";
	my $doc = $xml->createDocumentType("Bsml",$url);
	$xml->setDoctype($doc);
	$bsmlElem = $self->_addel( $xml, 'Bsml');
	$defsElem = $self->_addel( $bsmlElem, 'Definitions');
	$seqsElem = $self->_addel( $defsElem, 'Sequences');
	unless ($args->{NODISP}) {
	    $dispElem = $self->_addel( $bsmlElem, 'Display');
	    my $stylElem = $self->_addel( $dispElem, 'Styles');
	    my $style = $self->_addel( $stylElem, 'Style', {
		type => "text/css" });
	    my $styleText = 
		qq(Interval-widget { display : "1"; }\n) .
		    qq(Feature { display-auto : "1"; });
	    $style->appendChild( $xml->createTextNode($styleText) );
	}
    }

    # Establish fundamental BSML elements, if they do not already exist
    $bsmlElem ||= $xml->getElementsByTagName("Bsml")->item(0);
    $defsElem ||= $xml->getElementsByTagName("Definitions")->item(0);
    $seqsElem ||= $xml->getElementsByTagName("Sequences")->item(0);
    
    ###############
    # <Sequences> #
    ###############

    # Map over Bio::Seq to BSML
    my %mol = ('dna' => 'DNA', 'rna' => 'RNA', 'protein' => 'AA');
    my @xmlSequences;

    foreach my $bioSeq (@{$seqref}) {
	my $xmlSeq = $xml->createElement("Sequence");
	my $FTs    = $xml->createElement("Feature-tables");
	
	# Array references to hold <Reference> objects:
	my $seqRefs = []; my $featRefs = [];
	# Array references to hold <Attribute> values (not objects):
	my $seqDesc = [];
	push @{$seqDesc}, ["comment" , "This file generated to BSML 2.2 standards - joins will be collapsed to a single feature enclosing all members of the join"];
	push @{$seqDesc}, ["description" , eval{$bioSeq->desc}];
	foreach my $kwd ( eval{@{$bioSeq->keywords || []}} ) {
	    push @{$seqDesc}, ["keyword" , $kwd];
	}
	push @{$seqDesc}, ["version" , eval{$bioSeq->seq_version}];
	push @{$seqDesc}, ["division" , eval{$bioSeq->division}];
	push @{$seqDesc}, ["pid" , eval{$bioSeq->pid}];
#	push @{$seqDesc}, ["bio_object" , ref($bioSeq)];
	my $pid = eval{$bioSeq->primary_id} || '';
	if( $pid ne $bioSeq ) {  
	    push @{$seqDesc}, ["primary_id" , eval{$bioSeq->primary_id}];
	}
	foreach my $dt (eval{$bioSeq->get_dates()} ) {
	    push @{$seqDesc}, ["date" , $dt];
	}
	foreach my $ac (eval{$bioSeq->get_secondary_accessions()} ) {
	    push @{$seqDesc}, ["secondary_accession" , $ac];
	}
	
	# Determine the accession number and a unique identifier
	my $acc = $bioSeq->accession_number eq "unknown" ?
	    "" : $bioSeq->accession_number;
	my $id;
	my $pi = $bioSeq->primary_id;
	if ($pi && $pi !~ /Bio::/) {
	    # Not sure I understand what primary_id is... It sometimes
	    # is a string describing a reference to a BioSeq object...
	    $id = "SEQ" . $bioSeq->primary_id;
	} else {
	    # Nothing useful found, make a new unique ID
	    $id = $acc || ("SEQ-io" . $idcounter->{Sequence}++);
	}
	# print "$id->",ref($bioSeq->primary_id),"\n";
	# An id field with spaces is interpreted as an idref - kill the spaces
	$id =~ s/ /-/g;
	# Map over <Sequence> attributes
	my %attr = ( 'title'         => $bioSeq->display_id,
		     'length'        => $bioSeq->length,
		     'ic-acckey'     => $acc,
		     'id'            => $id,
		     'representation' => 'raw',
		     );
	$attr{molecule} = $mol{ lc($bioSeq->molecule) } if $bioSeq->can('molecule');


	foreach my $a (keys %attr) {
	    $xmlSeq->setAttribute($a, $attr{$a}) if (defined $attr{$a} &&
						     $attr{$a} ne "");
	}
	# Orphaned Attributes:
	$xmlSeq->setAttribute('topology', 'circular') 
	    if ($bioSeq->is_circular);
	# <Sequence> strand, locus
	
	$self->_add_page($xml, $xmlSeq) if ($dispElem);
	################
	# <Attributes> #
	################

	# Check for Bio::Annotations on the * <Sequence> *.
	$self->_parse_annotation( -xml => $xml, -obj => $bioSeq, 
				  -desc => $seqDesc, -refs => $seqRefs);

	# Incorporate species data
	if (ref($bioSeq->species) eq 'Bio::Species') {
	    # Need to peer into Bio::Species ...
	    my @specs = ('common_name', 'genus', 'species', 'sub_species');
	    foreach my $sp (@specs) {
		next unless (my $val = $bioSeq->species()->$sp());
		push @{$seqDesc}, [$sp , $val];
	    }
	    push @{$seqDesc}, ['classification', 
			       (join " ", $bioSeq->species->classification) ];
	    # Species::binomial will return "genus species sub_species" ...
	} elsif (my $val = $bioSeq->species) {
	    # Ok, no idea what it is, just dump it in there...
	    push @{$seqDesc}, ["species", $val];
	}

	# Add the description <Attribute>s for the <Sequence>
	foreach my $seqD (@{$seqDesc}) {
	    $self->_addel($xmlSeq, "Attribute", {
		name => $seqD->[0], content => $seqD->[1]}) if ($seqD->[1]);
	}

	# If sequence references were added, make a Feature-table for them
	unless ($#{$seqRefs} < 0) {
	    my $seqFT = $self->_addel($FTs, "Feature-table", {
		title => "Sequence References", });
	    foreach my $feat (@{$seqRefs}) {
		$seqFT->appendChild($feat);
	    }
	}
	
	# This is the appropriate place to add <Feature-tables>
	$xmlSeq->appendChild($FTs);
	
	#############
	# <Feature> #
	#############	

#>>>>	# Perhaps it is better to loop through top_Seqfeatures?...
#>>>>	# ...however, BSML does not have a hierarchy for Features
	
	if (defined $args->{SKIPFEAT} &&
	    $args->{SKIPFEAT} eq 'all') {
	    $args->{SKIPFEAT} = { all => 1};
	}
	foreach my $class (keys %{$args->{SKIPFEAT}}) {
	    $args->{SKIPFEAT}{lc($class)} = $args->{SKIPFEAT}{$class};
	}
	# Loop through all the features
	my @features = $bioSeq->all_SeqFeatures();
	if (@features && !$args->{SKIPFEAT}{all}) {
	    my $ft = $self->_addel($FTs, "Feature-table", {
		title => "Features", });
	    foreach my $bioFeat (@features ) {
		my $featDesc = [];
		my $class = lc($bioFeat->primary_tag);
		# The user may have specified to ignore this type of feature
		next if ($args->{SKIPFEAT}{$class});
		my $id = "FEAT-io" . $idcounter->{Feature}++;
		my $xmlFeat = $self->_addel( $ft, 'Feature', {
		    'id' => $id,
		    'class' => $class , 
		    'value-type' => $bioFeat->source_tag });
		# Check for Bio::Annotations on the * <Feature> *.
		$self->_parse_annotation( -xml => $xml, -obj => $bioFeat,
					  -desc => $featDesc, -id => $id,
					  -refs =>$featRefs, );
		# Add the description stuff for the <Feature>
		foreach my $de (@{$featDesc}) {
		    $self->_addel($xmlFeat, "Attribute", {
			name => $de->[0], content => $de->[1]}) if ($de->[1]);
		}
		$self->_parse_location($xml, $xmlFeat, $bioFeat);

		# loop through the tags, add them as <Qualifiers>
		next if (defined $args->{SKIPTAGS} &&
			 $args->{SKIPTAGS} =~ /all/i);
		# Tags can consume a lot of CPU cycles, and can often be
		# rather non-informative, so -skiptags can allow total or
		# selective omission of tags.
		foreach my $tag ($bioFeat->all_tags()) {
		    next if (exists $args->{SKIPTAGS}{$tag});
		    foreach my $val ($bioFeat->each_tag_value($tag)) {
			$self->_addel( $xmlFeat, 'Qualifier', {
			    'value-type' => $tag , 
			    'value' => $val });
		    }
		}
	    }
	}

	##############
	# <Seq-data> #
	##############	
	
	# Add sequence data
	if ( (my $data = $bioSeq->seq) && !$args->{NODATA} ) {
	    my $d = $self->_addel($xmlSeq, 'Seq-data');
	    $d->appendChild( $xml->createTextNode($data) );
	}

	# If references were added, make a Feature-table for them
	unless ($#{$featRefs} < 0) {
	    my $seqFT = $self->_addel($FTs, "Feature-table", {
		title => "Feature References", });
	    foreach my $feat (@{$featRefs}) {
		$seqFT->appendChild($feat);
	    }
	}
	
	# Place the completed <Sequence> tree as a child of <Sequences>
	$seqsElem->appendChild($xmlSeq);
	push @xmlSequences, $xmlSeq;
    }

    # Prevent browser crashes by explicitly closing empty elements:
    if ($args->{CLOSE}) {
	my @problemChild = ('Sequences', 'Sequence', 'Feature-tables', 
			    'Feature-table', 'Screen', 'View',);
	foreach my $kid (@problemChild) {
	    foreach my $prob ($xml->getElementsByTagName($kid)) {
		unless ($prob->hasChildNodes) {
		    $prob->appendChild(
			$xml->createComment(" Must close <$kid> explicitly "));
		}
	    }
	}
    }

    if (defined $args->{RETURN} && 
	$args->{RETURN} =~ /seq/i) {
	return \@xmlSequences;
    } else {
	return $xml;
    }
}

#line 823

sub write_seq {
    my $self = shift;
    my $args = $self->_parseparams( @_);
    if ($#_ == 0 ) {
	# If only a single value is passed, assume it is the seq object
	unshift @_, "-seq";
    }
    # Build a BSML XML DOM object based on the sequence(s)
    my $xml = $self->to_bsml( @_,
			      -return => undef );
    # Convert to a string
    my $out = $xml->toString;
    # Print after putting a return after each element - more readable
    $out =~ s/>/>\n/g;
    $self->_print("Content-type: " . $args->{PRINTMIME} . "\n\n") 
	if ($args->{PRINTMIME});
    $self->_print( $out );
    # Return the DOM tree in case the user wants to do something with it

    $self->flush if $self->_flush_on_write && defined $self->_fh;
    return $xml;
}

#line 867

    ###############################
    # <Interval-loc> & <Site-loc> #
    ###############################

sub _parse_location {
    my $self = shift;
    my ($xml, $xmlFeat, $bioFeat) = @_;
    my $bioLoc = $bioFeat->location;
    my @locations;
    if (ref($bioLoc) =~ /Split/) {
	@locations = $bioLoc->sub_Location;
	# BSML 2.2 does not recognize / support joins. For this reason,
	# we will just use the upper-level location. The line below can
	# be deleted or commented out if/when BSML 3 supports complex
	# interval deffinitions:
	@locations = ($bioLoc);
    } else {
	@locations = ($bioLoc);
    }
    my @added = ();
    
    # Add the site or interval positional information:
    foreach my $loc (@locations) {
	my ($start, $end) = ($loc->start, $loc->end);
	my %locAttr;
	# Strand information is not well described in BSML
	$locAttr{complement} = 1 if ($loc->strand == -1);
	if ($start ne "" && ($start == $end || $end eq "")) {
	    $locAttr{sitepos} = $start;
	    push @added, $self->_addel($xmlFeat,'Site-loc',\%locAttr);
	} elsif ($start ne "" && $end ne "") {
	    if ($start > $end) {
		# The feature is on the complementary strand
		($start, $end) = ($end, $start);
		$locAttr{complement} = 1;
	    }
	    $locAttr{startpos} = $start;
	    $locAttr{endpos} = $end;
	    push @added, $self->_addel($xmlFeat,'Interval-loc',\%locAttr);
	} else {
	    warn "Failure to parse SeqFeature location. Start = '$start' & End = '$end'";
	}
    }
    return \@added;
}

#line 924

sub _parse_bsml_feature {
    my $self = shift;
    my ($feat) = @_;
    
    my $basegsf = new Bio::SeqFeature::Generic;
       # score
       # frame
       # source_tag

    # Use the class as the primary tag value, if it is present
    if ( my $val = $feat->getAttribute("class") ) {
	$basegsf->primary_tag($val);
    }

    # Positional information is in <Interval-loc>s or <Site-loc>s
    # We need to grab these in order, to try to recreate joins...
    my @locations = ();
    foreach my $kid ($feat->getChildNodes) {
	my $nodeName = $kid->getNodeName;
	next unless ($nodeName eq "Interval-loc" ||
		     $nodeName eq "Site-loc");
	push @locations, $kid;
    }
    if ($#locations == 0) {
	# There is only one location specified
	$self->_parse_bsml_location($locations[0], $basegsf);
    } elsif ($#locations > 0) {
#>>>>   # This is not working, I think the error is somewhere downstream
	# of add_sub_SeqFeature, probably in RangeI::union ?
	# The sub features are added fine, but the EXPANDed parent feature
	# location has a messed up start - Bio::SeqFeature::Generic ref
	# instead of an integer - and an incorrect end  - the end of the first
	# sub feature added, not of the union of all of them.

	# Also, the SeqIO::genbank.pm output is odd - the sub features appear
	# to be listed with the *previous* feature, not this one.

	foreach my $location (@locations) {
	    my $subgsf = $self->_parse_bsml_location($location);
	  #  print "start ", $subgsf->start,"\n";
	  #  print "end ", $subgsf->end,"\n";
	    $basegsf->add_sub_SeqFeature($subgsf, 'EXPAND');
	}
	# print $feat->getAttribute('id'),"\n";
	# print $basegsf->primary_tag,"\n";

    } else {
	# What to do if there are no locations? Nothing needed?
    }
    
    # Look at any <Attribute>s or <Qualifier>s that are present:
    my $floppies = &GETFLOPPIES($feat);
    foreach my $attr (@{$floppies}) {
	my ($name, $content) = &FLOPPYVALS($attr);
	
	if ($name =~ /xref/i) {
	    # Do we want to put these in DBLinks??
	}

	# Don't know what the object is, dump it to a tag:
	$basegsf->add_tag_value(lc($name), $content);
    }

    # Mostly this helps with debugging, but may be of utility...
    # Add a tag holding the BSML id value
    if ( (my $val = $feat->getAttribute('id')) &&
	 !$basegsf->has_tag('bsml-id')) {
	# Decided that this got a little sloppy...
#	$basegsf->add_tag_value("bsml-id", $val);
    }
    return $basegsf;
}

#line 1008

sub _parse_bsml_location {
    my $self = shift;
    my ($loc, $gsf) = @_;
    
    $gsf ||= new Bio::SeqFeature::Generic;
    my $type = $loc->getNodeName;
    my ($start, $end);
    if ($type eq 'Interval-loc') {
	$start = $loc->getAttribute('startpos');
	$end = $loc->getAttribute('endpos');
    } elsif ($type eq 'Site-loc') {
	$start = $end = $loc->getAttribute('sitepos');
    } else {
	warn "Unknown location type '$type', could not make GSF\n";
	return undef;
    }
    $gsf->start($start);
    $gsf->end($end);

    # BSML does not have an explicit method to set undefined strand
    if (my $s = $loc->getAttribute("complement")) {
	if ($s) {
	    $gsf->strand(-1);
	} else {
	    $gsf->strand(1);
	}
    } else {
	# We're setting "strand nonspecific" here - bad idea?
	# In most cases the user likely meant it to be on the + strand
	$gsf->strand(0);
    }
    
    return $gsf;
}

#line 1065

sub _parse_reference {
    my $self = shift;
    my $args = $self->_parseparams( @_);
    my ($xml, $ref, $refRef) = ($args->{XML}, $args->{REFOBJ}, $args->{REFS});

    ###############
    # <Reference> #
    ###############

    my $xmlRef = $xml->createElement("Reference");
#>> This may not be the right way to make a BSML dbxref...
    if (my $link = $ref->medline) {
	$xmlRef->setAttribute('dbxref', $link);
    }

    # Make attributes for some of the characteristics
    my %stuff = ( start => $ref->start,
		  end => $ref->end,
		  rp => $ref->rp, 
		  comment => $ref->comment,
		  pubmed => $ref->pubmed,
		  );
    foreach my $s (keys %stuff) {
	$self->_addel($xmlRef, "Attribute", {
	    name => $s, content => $stuff{$s} }) if ($stuff{$s});
    }
    $xmlRef->setAttribute('refs', $args->{ID}) if ($args->{ID});
    # Add the basic information
    # Should probably check for content before creation...
    $self->_addel($xmlRef, "RefAuthors")->
	appendChild( $xml->createTextNode(&STRIP($ref->authors)) );
    $self->_addel($xmlRef, "RefTitle")->
	appendChild( $xml->createTextNode(&STRIP($ref->title)) );
    $self->_addel($xmlRef, "RefJournal")->
	appendChild( $xml->createTextNode(&STRIP($ref->location)) );
    # References will be added later in a <Feature-Table>
    push @{$refRef}, $xmlRef;
}

#line 1131

sub _parse_annotation {
    my $self = shift;
    my $args = $self->_parseparams( @_);
    my ($xml, $obj, $descRef, $refRef) = 
	( $args->{XML}, $args->{OBJ}, $args->{DESC}, $args->{REFS} );
    # No good place to put any of this (except for references). Most stuff
    # just gets dumped to <Attribute>s
    my $ann = $obj->annotation;
    return undef unless ($ann);
#	use BMS::Branch; my $debug = BMS::Branch->new( ); warn "$obj :"; $debug->branch($ann);
    unless (ref($ann) =~ /Collection/) {
	# Old style annotation. It seems that Features still use this
	# form of object
	$self->_parse_annotation_old(@_);
	return;
    }

    foreach my $key ($ann->get_all_annotation_keys()) {
	foreach my $thing ($ann->get_Annotations($key)) {
	    if ($key eq 'description') {
		push @{$descRef}, ["description" , $thing->value];
	    } elsif ($key eq 'comment') {
		push @{$descRef}, ["comment" , $thing->text];
	    } elsif ($key eq 'dblink') {
		# DBLinks get dumped to attributes, too
		push @{$descRef}, ["db_xref" ,  $thing->database . ":" 
				   . $thing->primary_id ];
		if (my $com = $thing->comment) {
		    push @{$descRef}, ["link" , $com->text ];
		}
		
	    } elsif ($key eq 'reference') {
		$self->_parse_reference( @_, -refobj => $thing );
	    } elsif (ref($thing) =~ /SimpleValue/) {
		push @{$descRef}, [$key , $thing->value];
	    } else {
		# What is this??
		push @{$descRef}, ["error", "bsml.pm did not understand ".
				   "'$key' = '$thing'" ];
	    }
	}
    }
}

#line 1199

    ###############
    # <Reference> #
    ###############

sub _parse_annotation_old {
    my $self = shift;
    my $args = $self->_parseparams( @_);
    my ($xml, $obj, $descRef, $refRef) = 
	( $args->{XML}, $args->{OBJ}, $args->{DESC}, $args->{REFS} );
    # No good place to put any of this (except for references). Most stuff
    # just gets dumped to <Attribute>s
    if (my $ann = $obj->annotation) {
	push @{$descRef}, ["annotation", $ann->description];
	foreach my $com ($ann->each_Comment) {
	    push @{$descRef}, ["comment" , $com->text];
	}
	
	# Gene names just get dumped to <Attribute name="gene">
	foreach my $gene ($ann->each_gene_name) {
	    push @{$descRef}, ["gene" , $gene];
	}

	# DBLinks get dumped to attributes, too
	foreach my $link ($ann->each_DBLink) {
	    push @{$descRef}, ["db_xref" , 
			       $link->database . ":" . $link->primary_id ];
	    if (my $com = $link->comment) {
		push @{$descRef}, ["link" , $com->text ];
	    }
	}
	
	# References get produced and temporarily held
	foreach my $ref ($ann->each_Reference) {
	    $self->_parse_reference( @_, -refobj => $ref );
	}
    }
}

#line 1248

sub _add_page {
    my $self = shift;
    my ($xml, $seq) = @_;
    my $disp = $xml->getElementsByTagName("Display")->item(0);
    my $page = $self->_addel($disp, "Page");
    my ($width, $height) = ( 7.8, 5.5);
    my $screen = $self->_addel($page, "Screen", {
	width => $width, height => $height, });
#    $screen->appendChild($xml->createComment("Must close explicitly"));
    my $view = $self->_addel($page, "View", {
	seqref => $seq->getAttribute('id'),
	title => $seq->getAttribute('title'),
	title1 => "{NAME}",
	title2 => "{LENGTH} {UNIT}",
    });
    $self->_addel($view, "View-line-widget", { 
	shape => 'horizontal',
	hcenter => $width/2 + 0.7,
	'linear-length' => $width - 2,
    });
    $self->_addel($view, "View-axis-widget");
    return $page;
}


#line 1287

sub _addel {
    my $self = shift;
    my ($root, $name, $attr) = @_;

    # Find the DOM::Document for the parent
    my $doc = $root->getOwnerDocument || $root;
    my $elem = $doc->createElement($name);
    foreach my $a (keys %{$attr}) {
	$elem->setAttribute($a, $attr->{$a});
    }
    $root->appendChild($elem);
    return $elem;
}

#line 1311

sub _show_dna {
   my $obj = shift;
   if( @_ ) {
      my $value = shift;
      $obj->{'_show_dna'} = $value;
    }
    return $obj->{'_show_dna'};
}

#line 1331

sub _initialize {
  my($self,@args) = @_;

  $self->SUPER::_initialize(@args);  
  # hash for functions for decoding keys.
  $self->{'_func_ftunit_hash'} = {}; 
  $self->_show_dna(1); # sets this to one by default. People can change it 

  my %param = @args;  # From SeqIO.pm
  @param{ map { lc $_ } keys %param } = values %param; # lowercase keys
  if ( exists $param{-file} && $param{-file} !~ /^>/) {
      # Is it blasphemy to add your own keys to an object in another package?
      # domtree => the parsed DOM tree retruned by XML::DOM
      $self->{'domtree'} = $self->_parse_xml( $param{-file} );
      # current_node => the <Sequence> node next in line for next_seq
      $self->{'current_node'} = 0;
  }
    
  $self->sequence_factory( new Bio::Seq::SeqFactory
			   ( -verbose => $self->verbose(), 
			     -type => 'Bio::Seq::RichSeq')) 
      if( ! defined $self->sequence_factory );
}


#line 1370

sub _parseparams {
    my $self = shift;
    my %hash = ();
    my @param = @_;
    
    # Hacked out from Parse.pm
    # The next few lines strip out the '-' characters which
    # preceed the keys, and capitalizes them.
    for (my $i=0;$i<@param;$i+=2) {
        $param[$i]=~s/^\-//;
        $param[$i]=~tr/a-z/A-Z/;
    }
    pop @param if @param %2;  # not an even multiple
    %hash = @param;
    return \%hash;
}

#line 1397

sub _parse_xml {
    my $self = shift;
    my $file = shift;
    
    unless (-e $file) {
	$self->throw("Could not parse non-existant XML file '$file'.");
	return undef;
    }
    my $parser = new XML::DOM::Parser;
    my $doc = $parser->parsefile ($file);
    return $doc;
}

sub DESTROY {
    my $self = shift;
    # Reports off the net imply that DOM::Parser will memory leak if you
    # do not explicitly dispose of it:
    # http://aspn.activestate.com/ASPN/Mail/Message/perl-xml/788458
    my $dom = $self->{'domtree'};
    # For some reason the domtree can get undef-ed somewhere...
    $dom->dispose if ($dom);
}


#line 1468


1;
