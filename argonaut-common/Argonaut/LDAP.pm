#!/usr/bin/perl -l -s

#######################################################################
#
# Argonaut:LDAP - Support library for argonaut-* scripts to access LDAP
#
# Copyright (c) 2008 Landeshauptstadt München
# Copyright (C) 2011 FusionDirectory project
#
# Author: Matthias S. Benkmann
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#######################################################################

package Argonaut::LDAP;

use strict;
use warnings;

use 5.008;

use Carp;

use Net::LDAP;
use Net::LDAP::Util qw(escape_filter_value ldap_explode_dn);
use MIME::Base64;

our (@ISA, @EXPORT, @EXPORT_OK);

require Exporter; @ISA=('Exporter');

@EXPORT = qw();
@EXPORT_OK = qw(ldap_get_object printEntry printAttribute);

sub ldap_get_object
{
  my %a = @_;
  my ($ldap, $basedn, $user, $timeout, $filter, $debug, $objectClass, $cnou,
  $subquery, $sublevel, $subconflict, $attributeSelectionRegexes, $enctrigger, $format, $dups,
  $mergeResults) =   #NOTE: mergeResults only has an effect in list context
  ($a{ldap}, $a{basedn}, $a{user}, $a{timeout}, $a{filter}, $a{debug}, $a{objectClass}, $a{cnou}, 
  $a{subquery}, $a{sublevel}, $a{subconflict}, $a{attributeSelectionRegexes},
  $a{enctrigger}, $a{format}, $a{dups},$a{mergeResults});

  my $results;

  defined($mergeResults) or $mergeResults = 1;
  wantarray or $mergeResults = 1;

  if (defined($debug))
  {
    defined($enctrigger) or $enctrigger="[\x00-\x1f]";
    $enctrigger eq "none" and $enctrigger="^\x00\$";
    if (!defined($format) or ($format ne "a:v" and $format ne "v"))
    {
      $format="a:v";
    }
  }

  if (not defined($filter) or $filter eq "")
  {
    $filter = "";
  }
  else
  {
    $filter = "(" . $filter . ")" unless $filter =~ m/^\(.*\)$/;
  }

  $user = escape_filter_value($user);

  defined($timeout) or $timeout=10;

  if (defined($subquery))
  {
    defined($sublevel) or $sublevel=9999;
    defined($subconflict) or $subconflict=1;
    $subquery="(" . $subquery . ")" unless $subquery =~ m/^\(.*\)$/;
  }
  else
  {
    $sublevel=undef;
    $subconflict=undef;
  }

  if (defined($objectClass) and defined($cnou))
  {
    $objectClass = escape_filter_value($objectClass);
    $cnou = escape_filter_value($cnou);
  }
  else
  {
    $objectClass = undef;
    $cnou = undef;
  }


  if (defined($objectClass)) # looking for object
  {
    $results = $ldap->search(
                        base   => $basedn,
                        filter => "(&" . $filter . "(&(objectClass=$objectClass)(cn=$cnou))" . ")",
                        timelimit => $timeout,
                      );
    ($results->code == 0) or return error($results->error);
    if ($results->count == 0) 
    {
      $results = $ldap->search(
                        base   => $basedn,
                        filter => "(&" . $filter . "(&(objectClass=$objectClass)(ou=$cnou))" . ")",
                        timelimit => $timeout,
                      );
    }
    ($results->count == 0) and return error("Could not find data for object \"$objectClass/$cnou\"");
    ($results->count > 1) and return error("More than one object matches \"$objectClass/$cnou\"");
  }
  else # looking for user
  {
    $results = $ldap->search(
                        base   => $basedn,
                        filter => "(&" . $filter . "(|(&(objectClass=posixAccount)(uid=$user))(&(objectClass=posixGroup)(memberUid=$user)))" . ")",
                        timelimit => $timeout,
                      );
    ($results->code == 0) or return error($results->error);
    ($results->count == 0) and return error("Could not find data for user \"$user\"");
  }

  my @entries = $results->entries;

  if (defined($debug))
  {
    print "x:================= primary object and posixGroups  ==================";
    foreach my $entry (@entries)
    {
      printEntry($entry, [".*"], $enctrigger, $format);
      print "x:_______________________________________________________________";
    }
  }

  my ($userDN, $dnFilter) = collectDNs($results);
  defined($userDN) or return error();

  $results = $ldap->search(
                      base   => $basedn,
                      filter => "(&" . $filter . $dnFilter . ")",
                      timelimit => $timeout,
                    );
  ($results->code == 0) or return error($results->error);

  my @objectGroups = $results->entries;

  if (defined($debug))
  {
    print "x:================= gosaGroupOfNames ==================";
    foreach my $entry (@objectGroups)
    {
      printEntry($entry, [".*"], $enctrigger, $format);
      print "x:_______________________________________________________________";
    }
  }

  my $userEntry = Net::LDAP::Entry->new;
  my $posixGroupEntry = Net::LDAP::Entry->new;
  my $objectGroupEntry = Net::LDAP::Entry->new;
  my $objectPosixGroupEntry = Net::LDAP::Entry->new;
  my %userEntryPseudoPrefixes = ();
  my %posixGroupEntryPseudoPrefixes = ();
  my %objectGroupEntryPseudoPrefixes = ();
  my %objectPosixGroupEntryPseudoPrefixes = ();

  foreach my $entry (@entries)  # User node and posixGroups
  {
    if (defined($subquery)) 
    { 
      if (!integrateSubtrees($ldap, $timeout, $entry, $subquery)) {return error();}; 
    }
    
    my ($dest, $destPseudoPrefixes);
    if ($entry->dn eq $userDN) 
    { 
      $dest = $userEntry; 
      $destPseudoPrefixes = \%userEntryPseudoPrefixes;
    }
    else 
    { 
      $dest = $posixGroupEntry; 
      $destPseudoPrefixes = \%posixGroupEntryPseudoPrefixes;
    }
    
    copySelectedAttributes($entry, $dest, $attributeSelectionRegexes, 1, $sublevel, $subconflict, $destPseudoPrefixes);
  }
  
  foreach my $entry (@objectGroups) # object groups with direct and indirect membership
  {
    if (defined($subquery)) 
    { 
      if (!integrateSubtrees($ldap, $timeout, $entry, $subquery)) {return error();}; 
    }

    my ($dest, $destPseudoPrefixes);
    if (hasAttribute($entry, "member", $userDN))  #direct membership
    { 
      $dest = $objectGroupEntry; 
      $destPseudoPrefixes = \%objectGroupEntryPseudoPrefixes;
    }
    else  #indirect membership
    { 
      $dest = $objectPosixGroupEntry; 
      $destPseudoPrefixes = \%objectPosixGroupEntryPseudoPrefixes;
    }

    copySelectedAttributes($entry, $dest, $attributeSelectionRegexes, 1, $sublevel, $subconflict, $destPseudoPrefixes);
  }


  if (defined($debug))
  {
    print "x:================= attributes from primary object ==================";
    printEntry($userEntry, [".*"], $enctrigger, $format);
    print "x:================= attributes from posixGroups ==================";
    printEntry($posixGroupEntry, [".*"], $enctrigger, $format);
    print "x:=========== attributes from gosaGroupOfNames (direct membership) ============";
    printEntry($objectGroupEntry, [".*"], $enctrigger, $format);
    print "x:=========== attributes from gosaGroupOfNames (via posixGroup) ============";
    printEntry($objectPosixGroupEntry, [".*"], $enctrigger, $format);
  }


  # If $mergeResults is requested, we move all attributes to $userEntry.
  # If $mergeResults is not wanted, we still move those attributes which are
  # not merged (because only one value is allowed for them).
  my $attributesToMove;
  if ($mergeResults)
  {
    $attributesToMove = $attributeSelectionRegexes;
  }
  else
  {
    $attributesToMove = [grep(!/^@/, @$attributeSelectionRegexes)];
  }

  # Warnings are turned off here, because they've already been printed by the calls to
  # copySelectedAttributes above and there's no need to get every warning twice.
  # Besides, since we always copy to the same object we'd get lots of bogus warnings.
  moveSelectedAttributes($posixGroupEntry, $userEntry, $attributesToMove, 0, $sublevel, $subconflict, \%userEntryPseudoPrefixes);
  moveSelectedAttributes($objectGroupEntry, $userEntry, $attributesToMove, 0, $sublevel, $subconflict, \%userEntryPseudoPrefixes);
  moveSelectedAttributes($objectPosixGroupEntry, $userEntry, $attributesToMove, 0, $sublevel, $subconflict, \%userEntryPseudoPrefixes);

  $userEntry->dn($userDN);

  my @results = ($userEntry);
  if (not $mergeResults)
  {
    foreach my $additionalEntry ($posixGroupEntry, $objectGroupEntry, $objectPosixGroupEntry)
    {
      if ($additionalEntry->attributes) { push @results, $additionalEntry; }
    }
  }
  
   # Unfortunately Net::LDAP::Entry does not remove duplicate attribute values, so we
   # have to do it ourselves.  
  if (defined($dups) and not $dups)
  {
    foreach my $entry (@results)
    {
      foreach my $attr ($entry->attributes)
      {
        my %unique = ();
        my @values = ();
        my $r_values = $entry->get_value($attr, asref => 1);
        foreach my $value (@$r_values)
        {
          if (!exists($unique{$value}))
          {
            $unique{$value} = 1;
            push @values, $value;
          }
        }
        $entry->replace($attr, \@values);
      }
    }
  }

  if (wantarray)
  {
    return @results;
  }
  else
  {
    return $results[0];
  }
} # ldap_get_object()


# printEntry($entry, \@attributeSelectionRegexes, $enctrigger, $format, [$suppressDn])
# Prints out all attributes of $entry. The dn is only printed if it matches one of the
# regexes from @attributeSelectionRegexes and only if $suppressDn is false.
sub printEntry
{
  my ($entry, $r_regex, $enctrigger, $format, $suppressDn) = @_;
  defined($entry) or return error("printEntry called for undef");
  
  foreach my $rx (@$r_regex)
  {
    my $regex = $rx; # copy so that we don't change the original value
    if (substr($regex, 0, 1) eq "\@") { $regex = substr($regex,1); }
    $regex = "^" . $regex . "\$"; # always match complete string
    if (not($suppressDn) and "dn" =~ m/$regex/) 
    {
      my $dn = $entry->dn;
      defined($dn) or $dn = "<undefined>";
      printAttribute("dn", [$dn], $enctrigger, $format);
      last;
    }
  }
  
  foreach my $attr (sort $entry->attributes)
  {
    my $r_values = $entry->get_value($attr, asref => 1);
    printAttribute($attr, $r_values, $enctrigger, $format);
  }
}

# printAttribute($attr, \@values, $enctrigger, $format)
sub printAttribute
{
  my ($attr, $r_values, $enctrigger, $format) = @_;
  my %haveSeen;
  my $regex = qr($enctrigger);
  foreach my $value (sort @$r_values)
  {
    exists($haveSeen{$value}) and next;
    $haveSeen{$value} = 1;
    my $out = "";
    if ($value =~ m/$enctrigger/)
    {
      if ($format eq "a:v") { $out = $attr . ":: "; }
      $out = $out . encode_base64($value, "");
    }
    else
    {
      if ($format eq "a:v") { $out = $attr . ": "; }
      $out = $out . $value;
    }
    print $out;
  }
}

# integrateSubtrees($ldap, $timeout, $entry, $subquery)
# On error returns false, otherwise true.
sub integrateSubtrees
{
  my ($ldap, $timeout, $entry, $subquery) = @_;

  my $results = $ldap->search(
                      base   => $entry->dn,
                      filter => $subquery,
                      timelimit => $timeout,
                    );
  ($results->code == 0) or return error($results->error);
  
  foreach my $subentry ($results->entries)
  {
    ($subentry->dn eq $entry->dn) and next;

    my $dn = $subentry->dn;    
    $dn = substr($dn, 0, length($dn) - length($entry->dn) - 1); # -1 for ","
    
    my $x = ldap_explode_dn($dn, reverse => 1);
    my $attrPrefix = "";
    foreach my $part (@$x)
    {
      foreach my $str (sort values %$part)
      {
        $attrPrefix .= $str . "/";
      }
    }
    
    foreach my $attr ($subentry->attributes)
    {
      my $r_values = $subentry->get_value($attr, asref => 1);
      $entry->add($attrPrefix . $attr, $r_values);
    }
  }
  return 1;
}

# see copyMoveSelectedAttributes
sub copySelectedAttributes
{
  copyMoveSelectedAttributes(0, @_);
}

# see copyMoveSelectedAttributes
sub moveSelectedAttributes
{
  copyMoveSelectedAttributes(1, @_);
}

# copyMoveSelectedAttributes($move, $entry, $dest, \@attributeSelectionRegexes, 
#                                 $warn, $sublevel, $subconflict, \%destPseudoPrefixes)
# Copies those entries from $entry to $dest (both of type Net::LDAP::Entry)
# whose names match one of the regular expressions in the array @attributeSelectionRegexes.
# If an attribute is already present in $dest, conflict resolution is
# performed as detailed in the USAGE. In the case of a non-merge conflict, the attribute will
# not be copied, i.e. for conflicting non-merged attributes, $dest's existing
# values take precedence.
# If $warn is false, then no warning is printed in case of a non-merge conflicting attribute.
# $sublevel works as described in the USAGE.
# If $subconflict > 0 then an attribute whose name contains a slash will be considered to
# already exist in $dest iff %destPseudoPrefixes contains the string you get by removing
# the shortest suffix with $subconflict slashes from the attribute name.
# Before copySelectedAttributes returns, it adds all of the pseudo-prefixes of the
# copied attributes to %destPseudoPrefixes so that the next time they will give a conflict.
# If $move is true, the original attribute will be removed from its dataset, even if it
# was not copied due to a conflict.
sub copyMoveSelectedAttributes
{
  my ($move, $entry, $dest, $r_regex, $wrn, $sublevel, $subconflict, $destPseudoPrefixes) = @_;
  
  my @attrNames = $entry->attributes;
  my %newPseudoPrefixes = ();
  
  foreach my $rx (@$r_regex)
  {
    my $regex = $rx; # copy so that we don't change the original value
    ($regex eq "") and next;
    (scalar(@attrNames) == 0) and last;

    my $merge = 0;
    if (substr($regex, 0, 1) eq "\@")
    {
      $regex = substr($regex,1);
      $merge = 1;
    }

    $regex = "^" . $regex . "\$"; # always match complete string
    $regex = qr/$regex/i;         # case-insensitive match

    my @matching = grep(/$regex/, @attrNames); 
    @attrNames = grep(!/$regex/, @attrNames);
    
    foreach my $longattr (@matching)
    {
      my $attr = $longattr;
      if (defined($sublevel) and $sublevel < 9999) 
      { 
        $attr = suffixWithMaxSlashes($attr, $sublevel);
      }

      my $conflict = 0;      
      if (not $merge)
      {
        if (defined($subconflict) and $subconflict != 0 and index($attr, "/") >= 0)
        {
          my $conflicter = removeSuffixWithSlashes($attr, $subconflict);
          if (exists($$destPseudoPrefixes{$conflicter})) 
          { 
            $conflict = 1; 
          }
          else
          {
            $newPseudoPrefixes{$conflicter} = 1; # next time the same string will give a conflict
          }
        }
        elsif ($dest->exists($attr))
          { $conflict = 1; }

        $conflict and $wrn and print STDERR "WARNING: 2 sources with same precedence for attribute \"", $attr, "\"";
      }
      
      if (not $conflict)
      {
        my $r_values = $entry->get_value($longattr, asref => 1);
        $dest->add($attr => $r_values);
      }
      
      if ($move)  { $entry->delete($longattr); }
    }
  }
  
  my ($k, $v);
  while (($k,$v) = each %newPseudoPrefixes) { $$destPseudoPrefixes{$k} = $v; }
}


# $string = removeSuffixWithSlashes($string, $slashnum)
# Returns $string with the shortest suffix that contains $slashnum slashes removed.
# If $string contains fewer than $slashnum slashes, returns the empty string.
sub removeSuffixWithSlashes
{
  my ($string, $slashnum) = @_;

  my $pos = length($string);  
  while (--$slashnum >= 0)
  {
    $pos = rindex($string, "/", $pos-1);
    ($pos < 0) and return "";  # fewer slashes than required => return ""
  }
  
  return substr($string, 0, $pos);
}

# $string = suffixWithMaxSlashes($string, $slashnum)
# Returns the longest suffix of $string that contains at most $slashnum slashes.
sub suffixWithMaxSlashes
{
  my ($string, $slashnum) = @_;

  my $pos = length($string);  
  while ($slashnum-- >= 0)
  {
    $pos = rindex($string, "/", $pos-1);
    ($pos < 0) and return $string;  # fewer slashes than required max. => return original string
  }
  
  return substr($string, $pos + 1);
}

# ($userDN, $dnFilter) = collectDNs($results)
#   $results: return value from ldap->search. Only $results->entries is used.
#   ($userDN, $dnFilter): 
#        $userDN: the DN of the entry of objectClass posixAccount. 
#                 If there are multiple, the sub will return undef
#                 If there is none, the first entry's DN will be used.
#        $dnFilter: (|(member=DN1)(member=DN2)...) where DN1,... are the DNs of the entries.
sub collectDNs
{
  my $results = shift;
  my $userDN;
  my $dnFilter = "";
  my $firstDN;

  foreach my $entry ($results->entries)
  {
    defined($firstDN) or $firstDN = $entry->dn;
    if (hasAttribute($entry, "objectClass", "posixAccount"))
    {
      defined($userDN) and return error("2 posixAccounts for the same user");
      $userDN = $entry->dn;
    }
    $dnFilter = $dnFilter . "(member=" . escape_filter_value($entry->dn) . ")";
  }
  
  defined($userDN) or $userDN = $firstDN;
  $dnFilter = "(|" . $dnFilter . ")";
  return ($userDN, $dnFilter);
}


# $bool = hasAttribute($entry, $attrName, $attrValue)
#   Returns true iff the Net::LDAP::Entry $entry has 
#   an attribute named $attrName with value $attrValue.
sub hasAttribute
{
  my ($entry, $attrName, $attrValue) = @_;
  foreach my $attr ($entry->get_value($attrName))
  {
    if ($attr eq $attrValue)
    {
      return 1;
    }
  }
  return 0;
}

sub error
{
  if (@_)
  {
    carp "ERROR: ", @_;
  }
  if (wantarray)
  {
    return ();
  }
  else
  {
    return undef;
  }
}


1;

__END__

=head1 NAME

Argonaut::LDAP - Support library for argonaut-* scripts to access LDAP

=head1 SYNOPSIS

  use Argonaut::Common qw(:ldap);
  use Argonaut::LDAP qw(ldap_get_object);
 
  my $ldapinfo = argonaut_ldap_parse_config_ex(); #ref to hash
  my ($ldapbase,$ldapuris) = ($ldapinfo->{"LDAP_BASE"}, $ldapinfo->{"LDAP_URIS"});
 
  my $ldap = Net::LDAP->new( $ldapuris, timeout => $timeout ) or die; 
  $ldap->bind() ;  # anonymous bind

   # list context
  my @results = ldap_get_object(ldap => $ldap,
                                basedn => $ldapbase,
                                user => $user,
                                timeout => $timeout,
                                filter => $filter,
                                debug => $debug,
                                objectClass => $objectClass,
                                cnou => $cn,
                                subquery => $subquery,
                                sublevel => $sublevel,
                                subconflict => $subconflict,
                                attributeSelectionRegexes => \@attributeSelectionRegexes,
                                enctrigger => $enctrigger,
                                format => $format,
                                dups => $dups,
                                mergeResults => $mergeResults
                );

  @results or die;
  
   # scalar context
  my $result = ldap_get_object(...);
  $result or die;

=head1 DESCRIPTION of C<ldap_get_object>

C<ldap_get_object()> reads information about an object (usually a user, but can also be a
workstation, a POSIX group,...) from LDAP. C<ldap_get_object()> understands gosaGroupOfNames and
posixGroups and will not only return properties of the queried object itself but also properties 
inherited from groups of both types.

=head1 PARAMETERS

=over

=item B<ldap>

An object of type L<Net::LDAP> that is already bound. Required.

=item B<basedn>

The base DN to use for all searches. Required.

=item B<user>/B<cnou> and B<objectClass>

You must pass either C<user> or C<cnou>. 
If you pass C<user>, C<objectClass> is ignored and C<ldap_get_object()> will search for an object
with C<objectClass=posixAccount> and C<uid> equal to the value passed as C<user>.

If you pass C<cnou>, then you must also pass C<objectClass> and  C<ldap_get_object()> will
search for an object with the given C<objectClass> and a C<cn> equal to the value passed as C<cnou>. If
no such object is found, it will attempt to find an object with the given C<objectClass> and
C<ou> equal to the value of C<cnou>.

=item B<attributeSelectionRegexes> and B<CONFLICT RESOLUTION>

A reference to a an array of regular expressions (as strings) that select the attributes to be returned
and determines how to proceed in case there are multiple sources for an attribute 
(e.g. the user's posixAccount node and a posixGroup the user is a member of).

Each regex selects all attributes with matching names. 

If the regex starts with the character C<@> (which is ignored for the matching), 
then attribute values from different sources will be merged (i.e. the result will include all values).

If attributeRegex does NOT start with C<@>, then an attribute from the queried object's own node
beats a posix group, which beats an object group (=gosaGroupOfNames) that
includes the object directly which beats an object group that contains a posix group containing
the object. Object groups containing other object groups are not supported by FusionDirectory, so this
case cannot occur.

If 2 sources with the same precedence (e.g. 2 posix groups) provide an attribute
of the same name, selected by a regex that doesn not start with C<@>, then
a WARNING is signalled and the program picks one of the conflicting attributes.

If multiple attribute regexes match the same attribute, the 1st matching
attribute regex's presence or absence of C<@> determines conflict resolution.

Matching is always performed against the I<complete> attribute name as if the regex had
been enclosed in C<^...$>, i.e.
an attribute regex C<name> will NOT match an attribute called C<surname>. Neither will the regex
C<sur>.

Matching is always performed case-insensitive.

If the parameter C<attributeSelectionRegexes> is not passed, it defaults to C<@.*>.

=item B<mergeResults>

If C<mergeResults> is C<false> and C<ldap_get_object()> is evaluated in list context, then it
will return a list of L<Net::LDAP::Entry> objects where each object represents the attributes on a given
precedence level. The first entry gives the attributes that come from the own node, i.e. those with
the highest precedence.

Attributes selected with a non-C<@> regex, i.e. those for which only one source is permitted, are always
found in the first entry and only there. For these attributes all conflicting values from lower precedence
levels are always discarded, so C<mergeResults=false> only makes sense when requesting
merged attributes via C<@>.

If C<mergeResults> is C<true> (the default) or if C<ldap_get_object()> is evaluated in scalar context,
then only one L<Net::LDAP::Entry> will be returned that contains all of the requested attributes.

=item B<dups>

L<Net::LDAP::Entry> does not perform duplicate removal on its attribute value lists by default.
If C<dups=true> (the default), the results returned from C<ldap_get_object()> may contain attributes that contain 
duplicate entries. If this would confuse your code, pass C<dups=false> and duplicate values will be
eliminated (at the cost of a few CPU cycles).

=item B<timeout>

If C<timeout> is passed, LDAP requests will use a timeout of this number of seconds.
Note that this does I<not> mean that C<ldap_get_object> will finish
within this time limit, since several LDAP requests may be involved.

Default timeout is 10s.

=item B<filter>

C<filter> is an LDAP-Expression that will be ANDed with all user/object/group
searches done by this program.

Use this to filter by C<gosaUnitTag>.

=item B<subquery>

The C<subquery> parameter is an LDAP filter such as C<objectClass=gotoMenuItem>. For the subtrees
rooted at the object's own
node and at all of its containing groups' nodes, an LDAP query using this filter will be done.
The attributes of all of the objects resulting from these queries will be treated as if they
were attributes of the node at which the search was rooted. The names of these pseudo-attributes  
have the form C<foo/bar/attr>. 

=item B<sublevel> 

C<sublevel> specifies the maximum number of slashes the pseudo-attribute
names will contain. If the complete name of a pseudo-attribute 
has more slashes than the given number, the name will be shortened to the longest
suffix that contains this many slashes. Specifying a C<sublevel> of 0 will
effectively merge all subquery nodes with the user/object/group node
so that in the end result their attributes are indistinguishable from
those of the user/object/group node. 
  
Default C<sublevel> is 9999.

Note: attribute regex matching is performed on the full name with all slashes.

=item B<subconflict> 

C<subconflict> is a number that determines when 2 pseudo-attributes are treated as being
in conflict with each other. 2 pseudo-attributes are treated as
conflicting if the results of removing the shortest suffixes containing
C<subconflict> slashes from their names (shortened according to C<sublevel>) 
are identical. E.g. with C<subconflict=0>
the pseudo-attributes C<foo/bar> and C<foo/zoo> are not conflicting,
whereas with C<subconflict=1> they are. Default C<subconflict> is 1.

=item B<debug>

If C<debug> is C<true>, then lots of debug output (mostly all of the nodes considered in
constructing the result) is printed to stdout.

=item B<enctrigger>

This parameter is only relevant when C<debug> is C<true>. It affects the way, attribute values
are printed. If C<enctrigger> is passed, it is interpreted as a regular expression and all DNs and attribute 
values will be tested against this regex. Whenever a value matches, it will be output
base64 encoded. Matching is performed case-sensitive and unless ^ and $ are
used in the regex, matching substrings are enough to trigger encoding.

If no C<enctrigger> is specified, the default C<[\x00-\x1f]> is used (i.e. base64
encoding will be used whenever a value contains a control character).
If you pass C<enctrigger=none>, encoding will be completely disabled.

=item B<format>

This parameter is only relevant when C<debug> is C<true>. It affects the way, attribute values
are printed. Format C<"a:v"> means to print 
C<attributeName: value> pairs. Format C<v> means to print the values only.

=back

=head1 BUGS

Please report any bugs, or post any suggestions, to the fusiondirectory mailing list fusiondirectory-users or to
<https://forge.fusiondirectory.org/projects/argonaut-agents/issues/new>

=head1 LICENCE AND COPYRIGHT

This code is part of FusionDirectory <http://www.fusiondirectory.org>

=over 2

=item Copyright (C) 2008 Matthias S. Benkmann

=item Copyright (C) 2011 FusionDirectory project

=back

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

=cut
