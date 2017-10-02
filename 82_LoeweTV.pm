###############################################################################
# 
# Developed with Kate
#
#  (c) 2017 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
#  All rights reserved
#
#   Special thanks goes to comitters:
#       - der.einstein      Initiator and Commiter
#       - viegener          Thanks for many Commits
#
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#
# $Id$
#
###############################################################################
##
## - initial HTTPUtils modification
## - do setters
## - add queuing
## - work off queue from callback
## 0.0.27
## - RequestAccess status as reading --> access - accepted
## - removed LoeweTV_ResponseProcessing
## 0.0.28
## - framework to collect data from XML in hash for readings update
## - change mac, chassis,version as reading
## - sendRequest: rename RCkey to a generic param 
## - sendRequest: allow additional param (also as array)
## - add getter
## - add get volume and volume reading
## - add get mutea and mute reading
## 0.0.29

## - lists start with 0 (start index)
## - first tests with channellist / mediatiem
## - added channellist listofchannellist media item but without result eval
## 0.0.30

## 0.0.31
  
## - clean some old code
## - honor attribute channellist for get channellist 
## - grab channel and automatically extend list and queue getmediatiems
## 0.0.32

## - add wake on lan support
## 0.0.33
  
## - store mediaitem information 
## - use mediaitem information set channel
## - new attr maxchannel to limit number of channels loaded
## 0.0.35

## - change log level for logs
## - avoid endless loop for requestaccess 
## - connect as new set (for access) / devicedata+access in get
## - return channellist in sequence of original channel list return
## 0.0.36

## - zapToMedia - translate & to &amp;
## - test channellist with parameter - favlist0,favlist1 works
## - set switchToName
## - set switchToNumber
## 0.0.37

## - get MediaItem will only add data if channellist
## - get drarchive added - no analysis of data
## 0.0.38

## - new function LoeweTV_getTVMAC_setDEF run after firstRun to set hash->{TVMAC} and advanced Option in DEF
## 0.0.39

## - patch from der.einstein add player fubction remotekey
## 0.0.40

## - patch der.einstein read out "StreamingUrl" from CHannellist or GetMediaItem auslesen and insert to Channellist show with showchannellist
  
## - fix for missing LoeweTV_cl_streamingurl
## - fix remove devicedata in setter list
## - get feature call with readings 
## - get settings call 
## 0.0.42

## - add get presence to refresh presence status
## - If interval not set explicit - no repeated statusrequest
## - regularly get volume/mute/channellist
## - reset clientid on nonopresent
## - add _attr function to hash
## - start/stop presence and timerstatusrequest on disabled
## - activate timerstatusrequest
## 0.0.43



##
###############################################################################
###############################################################################
##  TODO
###############################################################################
## - 
## - 
## - 
## - getMediaItem to distinguish between call from channellist crawler or get command
## - 
## - get also media information for actual playback and store in readings
## - 
## - grab channel list of lists 
## - 
## - handle soap failures
##    <SOAP-ENV:Body>  <SOAP-ENV:Fault>   <faultcode>Server</faultcode>   <faultstring>URN 'urn:loewe.de:RemoteTV:Tablet' not found</faultstring>   
##   <faultactor>cSOAP_Server</faultactor>   <detail/>  </SOAP-ENV:Fault> </SOAP-ENV:Body></SOAP-ENV:Envelope>
## - 
## - 
## - calc fcid from uniqueid?
## - update state consistently?
##
###############################################################################




package main;

use strict;
use warnings;

use Data::Dumper::Simple;    # Kann später entfernt werden, nur zum Debuggen


my $missingModul = "";
eval "use LWP::UserAgent;1" or $missingModul .= "LWP::UserAgent ";
eval "use HTTP::Request::Common;1" or $missingModul .= "HTTP::Request::Common ";
eval "use XML::Twig;1" or $missingModul .= "XML::Twig ";

use Blocking;


my $version = "0.0.43";


# Declare functions
sub LoeweTV_Define($$);
sub LoeweTV_Undef($$);
sub LoeweTV_Initialize($);
sub LoeweTV_Set($@);
sub LoeweTV_Get($@);
sub LoeweTV_WakeUp_Udp($@);
sub LoeweTV_SendRequest($$;$$$);
sub LoeweTV_Presence($);
sub LoeweTV_PresenceRun($);
sub LoeweTV_PresenceDone($);
sub LoeweTV_PresenceAborted($);
sub LoeweTV_TimerStatusRequest($);
sub LoeweTV_Attr(@);
sub LoeweTV_IsPresent($);
sub LoeweTV_HasAccess($);
sub LoeweTV_ParseRequestAccess($$);

sub LoeweTV_hasChannelList($);
sub LoeweTV_NewChannelList($$);
sub LoeweTV_ChannelList_Reference($$);
sub LoeweTV_ChannelList_Reference($$);
sub LoeweTV_ChannelList_Fragment($$$$$);
sub LoeweTV_ChannelList_AddChannelXML($$$$$$);
sub LoeweTV_getAnElementForChannelUUID($$$);
sub LoeweTV_getNameForChannelUUID($$); 
sub LoeweTV_getLocatorForChannelUUID($$);
sub LoeweTV_getCaptionForChannelUUID($$);
sub LoeweTV_findUUIDForChannelName($$);
sub LoeweTV_findUUIDForChannelCaption($$);
sub LoeweTV_findUUIDForChannelLocator($$);
sub LoeweTV_ChannelListText($);
sub LoeweTV_GetChannelNames($$);
sub LoeweTV_PrepareReading($$$);
sub LoeweTV_getTVMAC_setDEF($$);


#########################
# Globals

my $LoeweTV_cl_uuid = 0;
my $LoeweTV_cl_locator = 1;
my $LoeweTV_cl_caption = 2;
my $LoeweTV_cl_shortinfo = 3;
my $LoeweTV_cl_streamingurl = 4;

#########################
# TYPE routines

sub LoeweTV_Initialize($) {
    my ($hash) = @_;
    
    $hash->{GetFn}      = "LoeweTV_Get";
    $hash->{SetFn}      = "LoeweTV_Set";
    $hash->{DefFn}      = "LoeweTV_Define";
    $hash->{UndefFn}    = "LoeweTV_Undef";

    $hash->{AttrFn}     = "LoeweTV_Attr";

    $hash->{AttrList}   =  "fhemMAC " .
                        "interval " .
                        "channellist " .
                        "maxchannel " .
                        "disable:1,0 disabledForIntervals ".
                        #"ip " .
                        #"tvmac " .
                        #"action " .
                        #"RCkey " .
                        #"clientid " .
                        #"fcid " .
                        "status:Accepted,Pending,Denied,undef " .
                        #"access:accepted,misc " .
                        #"pingresult:down,up " .
                        #"lastersponse " .
                        #"lastchunk " .
                        #"volstate " .
                        #"mutstate:0,1 " .
                        #"curlocator " .
                        #"curevent " .
                        #"nextevent " .
                        $readingFnAttributes;
                         
    foreach my $d(sort keys %{$modules{LoeweTV}{defptr}}) {
    
        my $hash = $modules{LoeweTV}{defptr}{$d};
        $hash->{VERSION}      = $version;
    }
}

sub LoeweTV_Define($$) {

    my ( $hash, $def )  = @_;
    
    my @a               = split( "[ \t][ \t]*", $def );


    return "too few parameters: define <NAME> LoeweTV <HOST> <MAC-TV>" if( @a < 3 or @a > 4 );
    return "Cannot define Loewe device. Perl modul ${missingModul}is missing." if ( $missingModul );

    
    my $name            = $hash->{NAME};
    my $host            = $a[2];
    
    $hash->{HOST}       = $host;
    $hash->{FCID}       = 1234;
    $hash->{TVMAC}      = $a[3] if(defined($a[3]));
    $hash->{VERSION}    = $version;
    $hash->{INTERVAL}   = 0;
    $hash->{CLIENTID}   = "?";
    
    
    Log3 $name, 3, "LoeweTV $name: defined LoeweTV device";
    
    $modules{LoeweTV}{defptr}{HOST} = $hash;
    readingsSingleUpdate($hash,'state','initialized',1);
    
    if( $init_done ) {
        InternalTimer( gettimeofday()+5, "LoeweTV_TimerStatusRequest", $hash, 0 );
    } else {
        InternalTimer( gettimeofday()+30, "LoeweTV_TimerStatusRequest", $hash, 0 );
    }
    
    return undef;
}

sub LoeweTV_Undef($$) {

    my ( $hash, $arg ) = @_;


    #RemoveInternalTimer($hash);
    delete $modules{LoeweTV}{defptr}{HOST} if( defined($modules{LoeweTV}{defptr}{HOST}) );

    return undef;
}

#########################
# Device Instance routines
sub LoeweTV_Attr(@) {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};
    
    my $orig = $attrVal;

    
    if( $attrName eq "disable" ) {
        if( $cmd eq "set" and $attrVal eq "1" ) {
            readingsSingleUpdate ( $hash, "state", "disabled", 1 );
            $hash->{PARTIAL} = '';
            RemoveInternalTimer($hash);
            Log3 $name, 3, "LoeweTV ($name) - disabled";
        } elsif( $cmd eq "set" and $attrVal eq "0" ) {
            RemoveInternalTimer($hash);
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "LoeweTV ($name) - enabled";
            LoeweTV_TimerStatusRequest($hash);
        } elsif( $cmd eq "del" ) {
            RemoveInternalTimer($hash);
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "LoeweTV ($name) - enabled";
            LoeweTV_TimerStatusRequest($hash);
        }
    }
    
    elsif( $attrName eq "disabledForIntervals" ) {
        if( $cmd eq "set" ) {
            Log3 $name, 4, "LoeweTV ($name) - enable disabledForIntervals";
            readingsSingleUpdate ( $hash, "state", "Unknown", 1 );
        }

        elsif( $cmd eq "del" ) {
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 4, "LoeweTV ($name) - delete disabledForIntervals";
        }
    }
    
    elsif( $attrName eq "interval" ) {
        if( $cmd eq "set" ) {
            $hash->{INTERVAL}   = $attrVal;
            RemoveInternalTimer($hash);
            Log3 $name, 4, "LoeweTV ($name) - set interval: $attrVal";
            LoeweTV_TimerStatusRequest($hash);
        }

        elsif( $cmd eq "del" ) {
            $hash->{INTERVAL}   = 0;
            RemoveInternalTimer($hash);
            Log3 $name, 4, "LoeweTV ($name) - delete User interval and set default: 300";
            LoeweTV_TimerStatusRequest($hash);
        }
        
    }

    return undef;
}

sub LoeweTV_Set($@) {
    
    my ($hash, $name, $cmd, @args) = @_;
    
    my ($action,$actPar1, $actPar2);

    my @actionargs;
    
    if( lc $cmd eq 'setactionfield' ) {

        return "$cmd needs text to show" if ( ( scalar( @args ) != 1 ) );
        @actionargs = ( 'SetActionField', $args[0] );

    } elsif( lc $cmd eq 'volume' ) {
        return "$cmd needs volume" if ( ( scalar( @args ) != 1 ) || ( $args[0] !~ /^\d+$/ ) );
        # value range is between 0 - 999999
        @actionargs = ( 'SetVolume', $args[0] );    
    
    } elsif( lc $cmd eq 'mute' ) {
        return "$cmd needs argument on or off " if ( ( scalar( @args ) != 1 ) || ( $args[0] !~ /^(on|off)$/ ) );
        @actionargs = ( 'SetMute', ( $args[0] eq "on" )?1:0 );    
        
    } elsif( lc $cmd eq 'wakeup' ) {
    
        LoeweTV_WakeUp_Udp($hash,$hash->{TVMAC},'255.255.255.255') if( defined($hash->{TVMAC}) );
        return;
    
    } elsif( lc $cmd eq 'remotekey' ) {
        #return "$cmd needs argument remote key" if ( ( scalar( @args ) != 1 ) || ( $args[0] !~ /^\d+$/ ) );
        return "$cmd needs argument remote key" if ( ( scalar( @args ) != 1 ) );
        @actionargs = ( 'InjectRCKey', $args[0] );    
    
    } elsif( lc $cmd eq 'connect' ) {
        @actionargs = ( 'RequestAccess');    
   
    } elsif( lc $cmd eq 'switchto' ) {
    
        return "$cmd needs locator" if ( ( scalar( @args ) != 1 ) );
        
        @actionargs = ( 'ZapToMedia', $args[0] );
    } elsif( lc $cmd eq 'switchtoname' ) {
    
        return "$cmd needs  name" if ( ( scalar( @args ) != 1 ) );
        return "Channellist not loaded" if ( ! LoeweTV_hasChannelList( $hash ) );
        
        my $oname = $args[0];
        $oname =~ s/`´/,/g;
        $oname =~ s/`_´/°°°/g;
        $oname =~ s/_/ /g;
        $oname =~ s/°°°/_/g;
        my $uuid = LoeweTV_findUUIDForChannelName( $hash, $oname );
        return "$cmd Channel name (".$oname.") not found " if ( ! defined( $uuid ) );
        my $locator = LoeweTV_getLocatorForChannelUUID( $hash, $uuid );
        @actionargs = ( 'ZapToMedia', $locator );

    } elsif( lc $cmd eq 'switchtonumber' ) {
    
        return "$cmd needs channel" if ( ( scalar( @args ) != 1 ) );
        return "$cmd needs channel number" if ( $args[0] !~ /^[0-9]+$/ );
        return "Channellist not loaded" if ( ! LoeweTV_hasChannelList( $hash ) );
        
        my $uuid = LoeweTV_findUUIDForChannelCaption( $hash, $args[0] );
        return "$cmd Channel number (".$args[0].") not found " if ( ! defined( $uuid ) );
        my $locator = LoeweTV_getLocatorForChannelUUID( $hash, $uuid );
        @actionargs = ( 'ZapToMedia', $locator );

    } else {
    
        my $list    = "SetActionField volume:slider,0,1,100 RemoteKey mute:on,off WakeUp:noArg connect:noArg ".
                      " switchTo switchToNumber ";
        if ( LoeweTV_hasChannelList( $hash ) ) {
          my $onames = LoeweTV_GetChannelNames( $hash, "`´" );
          $onames =~ s/_/°°°/g;
          $onames =~ s/ /_/g;
          $onames =~ s/°°°/`_´/g;
          $onames =~ s/`´/,/g;
          $list .= " switchToName:".$onames." ";
          #Debug "onames :".$onames.":";
        }
        
        return "Unknown argument $cmd, choose one of $list";
    }

    
    if ( scalar(@actionargs) > 0 ) {
      # 
      return "LoeweTV $name is not present" if( ! LoeweTV_IsPresent( $hash ));
      LoeweTV_SendRequest($hash,$actionargs[0],$actionargs[1],$actionargs[2]);
    }
    
    Log3 $name, 4, "LoeweTV $name: called function LoeweTV_Set()";
    return undef;
}

sub LoeweTV_Get($@) {
    
    my ($hash, $name, $cmd, @args) = @_;
    
    my ($action,$actPar1, $actPar2);

    my @actionargs;
    
    if( lc $cmd eq 'showchannellist' ) {
      return LoeweTV_ChannelListText( $hash );

    } elsif( lc $cmd eq 'presence' ) {
      LoeweTV_Presence($hash);
      return;

    } elsif( lc $cmd eq 'access' ) {
        @actionargs = ( 'RequestAccess');    
        
    } elsif( lc $cmd eq 'devicedata' ) {
        @actionargs = ( 'GetDeviceData');    
   
    } elsif( lc $cmd eq 'volume' ) {
        # value range is between 0 - 999999
        @actionargs = ( 'GetVolume' );    
    
    } elsif( lc $cmd eq 'mute' ) {
        @actionargs = ( 'GetMute' );    
    
    } elsif( lc $cmd eq 'feature' ) {
        $args[0] = "remote-app" if ( ( scalar( @args ) < 1 )  );
        @actionargs = ( 'GetFeature' );    

    } elsif( lc $cmd eq 'currentplayback' ) {
        @actionargs = ( 'GetCurrentPlayback' );    
        
    } elsif( lc $cmd eq 'listofchannellists' ) {
        $args[0] = 0 if ( ( scalar( @args ) < 1 ) || ( $args[0] !~ /^\d+$/ ) );
        @actionargs = ( 'GetListOfChannelLists', $args[0] );    
        
    } elsif( lc $cmd eq 'channellist' ) {
        $args[0] = AttrVal($name,"channellist","default") if ( ( scalar( @args ) < 1 ) );
        $args[1] = 0 if ( ( scalar( @args ) < 2 ) || ( $args[1] !~ /^\d+$/ ) );
        @actionargs = ( 'GetChannelList', $args[0], $args[1] );    
        # Need to reset count to ensure calculation of min/max fragments
        $hash->{helper}{ChannelListCount} = 0;        
        $hash->{helper}{ChannelListView} = "";

    } elsif( lc $cmd eq 'drarchive' ) {
        $args[0] = 0 if ( ( scalar( @args ) < 1 ) || ( $args[0] !~ /^\d+$/ ) );
        @actionargs = ( 'GetDRPlusArchive', $args[0] );    
        # Need to reset count to ensure calculation of min/max fragments
        $hash->{helper}{ChannelListCount} = 0;        
        $hash->{helper}{ChannelListView} = "";
        
    } elsif( lc $cmd eq 'mediaitem' ) {
        return "$cmd needs a uuid of a media item" if ( scalar( @args ) != 1 );
        @actionargs = ( 'GetMediaItem', $args[0] );    
        
    } elsif( lc $cmd eq 'access' ) {
        @actionargs = ( 'RequestAccess');    
        
    } elsif( lc $cmd eq 'devicedata' ) {
        @actionargs = ( 'GetDeviceData');    
   
    } elsif( lc $cmd eq 'settings' ) {
        @actionargs = ( 'GetSettings');    
   
    } elsif( lc $cmd eq 'currentevent' ) {
    
        @actionargs = ( 'GetCurrentEvent' );
        
    } elsif( lc $cmd eq 'nextevent' ) {
    
        @actionargs = ( 'GetNextEvent' );
        
    } else {
    
        my $list    = "volume:noArg mute:noArg currentplayback:noArg ".
              "access:noArg devicedata:noArg feature settings presence:noArg ".
              "listofchannellists channellist drarchive mediaitem currentevent:noArg nextevent:noArg showchannellist:noArg";
        
        return "Unknown argument $cmd, choose one of $list";
    }

    
    if ( scalar(@actionargs) > 0 ) {
      # 
      return "LoeweTV $name is not present" if( ! LoeweTV_IsPresent( $hash ));
      LoeweTV_SendRequest($hash,$actionargs[0],$actionargs[1],$actionargs[2]);
    }
    
    Log3 $name, 4, "LoeweTV $name: called function LoeweTV_Get()";
    return undef;
}

sub LoeweTV_TimerStatusRequest($) {

### Hier kommen dann die Sachen rein welche alle x Sekunden ausfegührt werden um Infos zu erhalten
### presence zum Beispiel

    my $hash        = shift;
    my $name        = $hash->{NAME};
    
    # Do nothing when disabled (also for intervals)
    if(! IsDisabled( $name )) {

        Log3 $name, 4, "Sub LoeweTV_TimerStatusRequest ($name) - start requests";

        if(LoeweTV_IsPresent( $hash )) {
        
          # do sendrequests only every second call
          if ( $hash->{TVSTATUS} ) {
    
            # handle regular requests if present
            #   deviceData, mute, volume, currentEvent
            LoeweTV_SendRequest($hash,'GetDeviceData');
            LoeweTV_SendRequest($hash,'GetVolume');
            LoeweTV_SendRequest($hash,'GetMute');
            LoeweTV_SendRequest($hash,'GetCurrentEvent');
            # ??? LoeweTV_SendRequest($hash,'GetCurrentPlayback');

            # if channellist not defined request channels
            if ( ! defined( $hash->{helper}{ChannelList} ) ) {
              my $cl = AttrVal($name,"channellist","default");
              LoeweTV_SendRequest($hash,'GetChannelList',$cl, 0 );
            }
            $hash->{TVSTATUS} = 0;
          } else {
            $hash->{TVSTATUS} = 1;
          }
          
        } else {
            # reset client id if not present - to force new connect
            $hash->{CLIENTID}   = "?";
            
            # update state
            readingsSingleUpdate($hash,'state','off',1);
        }

        # start blocking presence call
        LoeweTV_Presence($hash);

    }
      
    Log3 $name, 5, "Sub LoeweTV_TimerStatusRequest ($name) - Done - new sequence - ".$hash->{INTERVAL}." s";
    if ( $hash->{INTERVAL} > 0 ) {
      InternalTimer( gettimeofday()+$hash->{INTERVAL}, "LoeweTV_TimerStatusRequest", $hash, 1 );
    }

}

# method to wake via lan, taken from Net::Wake package
sub LoeweTV_WakeUp_Udp($@) {

    my ($hash,$mac_addr,$host,$port) = @_;
    my $name  = $hash->{NAME};


    $port = 9 if (!defined $port || $port !~ /^\d+$/ );

    my $sock = new IO::Socket::INET(Proto=>'udp') or die "socket : $!";
    if(!$sock) {
        Log3 $name, 2, "Sub LoeweTV_WakeUp_Udp ($name) - Can't create WOL socket";
        return 1;
    }
  
    my $ip_addr   = inet_aton($host);
    my $sock_addr = sockaddr_in($port, $ip_addr);
    $mac_addr     =~ s/://g;
    my $packet    = pack('C6H*', 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, $mac_addr x 16);

    setsockopt($sock, SOL_SOCKET, SO_BROADCAST, 1) or die "setsockopt : $!";
    send($sock, $packet, 0, $sock_addr) or die "send : $!";
    close ($sock);

    return 1;
}


sub LoeweTV_ParseRequestAccess($$) {
    
    my ($hash,$access)        = @_;
    
    my $name                    = $hash->{NAME};
 
    return if ( ! defined($access) );
    
    if ( ( lc $access eq "accepted" ) ) {
      readingsSingleUpdate($hash,'state','connected',1);
      readingsSingleUpdate($hash,'access','accepted',1);
    } elsif ( ( lc $access eq "pending" ) ) {
      readingsSingleUpdate($hash,'state','connected',1);
      readingsSingleUpdate($hash,'access','pending',1);
      # queue another request on pending
      LoeweTV_SendRequest($hash,'RequestAccess');
    } else {
      Log3 $name, 2, "LoeweTV_ParseRequestAccess $name: not connected";
      readingsSingleUpdate($hash,'access',$access,1);
      readingsSingleUpdate($hash,'state','disconnected',1);
    }
 
} 





sub LoeweTV_PrepareReading($$$) {
    
    my ($hash,$rname, $rvalue)        = @_;
    
    my $name                    = $hash->{NAME};
 
    my $refreadings = $hash->{HU_SR_PARAMS}->{SR_READINGS};
    
    Log3 $name, 4, "LoeweTV_PrepareReading $name: reading: ".$rname."   value :".$rvalue.":";
    $refreadings->{$rname} = $rvalue;
}
 
# Pars
#   hash
#   action 
#   opt: par1 (RCkey - migt be also representing differnt par)
#   opt: par2 addtl pars
#   opt: retrycount - will be set to 0 if not given (meaning first exec)
sub LoeweTV_SendRequest($$;$$$) {

    my ( $hash, @args) = @_;

    my ( $action, $actPar1, $actPar2, $retryCount) = @args;
    my $name = $hash->{NAME};
  
    my $ret;
    my $alphabet;
  
    Log3 $name, 5, "LoeweTV_SendRequest $name: ";
    
    $retryCount = 0 if ( ! defined( $retryCount ) );
    # increase retrycount for next try
    $args[3] = $retryCount+1;
    
#    my ($message, $response, $request, $userAgent, $noob, $twig2, $content, $handlers);
    my ($message, $request, $content, $handlers);
    our $result ="";
    
    my $actionString = $action.(defined($actPar1)?"  Par1:".$actPar1.":":"")."  ".(defined($actPar2)?"  Par2:".$actPar2.":":"");

    Log3 $name, 4, "LoeweTV_SendRequest $name: called with action ".$actionString;
    
    # ensure actionQueue exists
    $hash->{actionQueue} = [] if ( ! defined( $hash->{actionQueue} ) );

    # Queue if not yet retried and currently waiting
    if ( ( defined( $hash->{doStatus} ) ) && ( $hash->{doStatus} =~ /^WAITING/ ) && (  $retryCount == 0 ) ){
      # add to queue
      Log3 $name, 4, "LoeweTV_SendRequest $name: add action to queue - args: ".$actionString;
      # RequestAccess will always be added to the beginning of the queue
      if ( ( $action eq "RequestAccess" ) )  {
        unshift( @{ $hash->{actionQueue} }, \@args );
      } else {
        push( @{ $hash->{actionQueue} }, \@args );
      }
      return;
    }  

    #######################
    # check authentication otherwise queue the current cmd and do authenticate first
    # but only if not already done once 
    # (pending will create another send request automatically first might return pending before accepted is returned)
    if ( ($action ne "RequestAccess") && ( ! LoeweTV_HasAccess($hash) ) && ( $retryCount == 0 ) ) {
      # add to queue
      Log3 $name, 4, "LoeweTV_SendRequest $name: add action to queue - args ".$actionString;
      push( @{ $hash->{actionQueue} }, \@args );
      
      $action = "RequestAccess";
      $actPar1 = undef;
      $actPar2 = undef;
      # update cmdstring
      $actionString = $action.(defined($actPar1)?"  Par1:".$actPar1.":":"")."  ".(defined($actPar2)?"  Par2:".$actPar2.":":"");
    } 
  
    $hash->{doStatus} = "WAITING";
    $hash->{doStatus} .= " retry $retryCount" if ( $retryCount > 0 );
    
    my %actions = (
        "RequestAccess"         =>  [sub {$content='<ltv:DeviceType>Homeautomation</ltv:DeviceType>
                                        <ltv:DeviceName>FHEM</ltv:DeviceName>
                                        <ltv:DeviceUUID>'.$hash->{TVMAC}.'</ltv:DeviceUUID>
                                        <ltv:RequesterName>FHEM</ltv:RequesterName>'},
                                        {'m:ClientId' => sub {$hash->{CLIENTID} = $_->text_only('m:ClientId')},
                                        'm:AccessStatus' => sub {LoeweTV_ParseRequestAccess($hash, $_->text_only('m:AccessStatus'));},}
                                    ],
                                    
        "InjectRCKey"           =>  [sub {
                                        if ( index($actPar1, "hdr" ) != -1 ) {
                                            $actPar1 =~ s/hdr// ;
                                            $alphabet = "l2700-hdr" ;
                                            
                                        } else { 
                                            $alphabet = "l2700" ; 
                                        };
                                        $content='<InputEventSequence>
                                        <RCKeyEvent alphabet="'.$alphabet.'" value="'.$actPar1.'" mode="press"/>
                                        <RCKeyEvent alphabet="'.$alphabet.'" value="'.$actPar1.'" mode="release"/>
                                        </InputEventSequence>'},{"ltv:InjectRCKey" => sub {$hash->{helper}{lastchunk} = $_->text_only();}},],
                                        
        "GetDeviceData"         =>  [sub {$content='';},
                                     {"m:MAC-Address" => sub {LoeweTV_getTVMAC_setDEF($hash, $_->text("m:MAC-Address"));},"m:Chassis" => sub {LoeweTV_PrepareReading($hash,"Chassis",$_->text("m:Chassis"));},"m:SW-Version" => sub {LoeweTV_PrepareReading($hash,"SW_Version",$_->text("m:SW-Version"));}}],
            
        "SetVolume"             => [sub {$content="<Value>".($actPar1*10000)."</Value>"},
                                    {"m:Value" => sub {LoeweTV_PrepareReading($hash,"volume", int(($_->text ("m:Value")/10000)+0.5));}}
                                    ],
        "GetVolume"             => [sub {$content="";},
                                    {"m:Value" => sub {LoeweTV_PrepareReading($hash,"volume", int(($_->text ("m:Value")/10000)+0.5));}}
                                    ],
        "SetMute"             => [sub {$content="<Value>".$actPar1."</Value>"},
                                    {"m:Value" => sub {LoeweTV_PrepareReading($hash,"mute", $_->text ("m:Value"));}}
                                    ],
            
        "GetMute"             => [sub {$content=""},
                                    {"m:Value" => sub {LoeweTV_PrepareReading($hash,"mute", $_->text ("m:Value"));}}
                                    ],
        "GetSettings"         => [sub {$content=""}
                                    ],

        "GetFeature"           => [sub {$content='<ltv:Name>'.$actPar1.'</ltv:Name>'},
                                    {"m:Status" => sub {LoeweTV_PrepareReading($hash,"feature_$actPar1", $_->text ("m:Status"));}}
                                    ],
        "GetChannelList"        =>  [sub { my $clc = (defined( $hash->{helper}{ChannelListCount})?$hash->{helper}{ChannelListCount}:0);
                                        $content="<ltv:ChannelListView>".$actPar1."</ltv:ChannelListView>
                                        <ltv:QueryParameters>
                                        <ltv:Range startIndex='".(defined($actPar2)?$actPar2:0).
                                            "' maxItems='".maxNum(0,minNum(100,AttrVal($name,"maxchannel",1000000)-$clc))."'/>
                                        <ltv:OrderField field='userChannelNumber' type='ascending'/>
                                        </ltv:QueryParameters>";$result="m:GetChannelListResponse"},
                                        {"m:ChannelListView" => sub { LoeweTV_NewChannelList( $hash, $_->text_only('m:ChannelListView') );},
                                          "m:ResultItemFragment" => sub { LoeweTV_ChannelList_Fragment( $hash, $_->att("sequenceNumber"), $_->att("totalResults"), $_->att("returnedResults"), $_->att("startIndex") );},
                                        "m:ResultItemReference" => sub { LoeweTV_ChannelList_Reference( $hash, $_->att("mediaItemUuid") );}}
                                    ],
        "GetMediaItem"          =>  [sub {$content='<MediaItemReference mediaItemUuid="'.$actPar1.'"/>';$result="m:ShortInfo"},
                                        {"m:ResultItem" => sub { if ( defined( $actPar2 ) ) {
                                            LoeweTV_ChannelList_AddChannelXML( $hash, 
                                                $_->get_xpath('.//m:uuid', 0), $_->get_xpath('.//m:Locator', 0), 
                                                $_->get_xpath('.//m:Caption', 0), $_->get_xpath('.//m:ShortInfo', 0),
                                                $_->get_xpath('.//m:StreamingUrl', 0) );}}}
                                    ],
########## in progress            

"GetListOfChannelLists" =>  [sub {$content="<ltv:QueryParameters>
                                        <ltv:Range startIndex='".$actPar1."' maxItems='".($actPar1+5)."'/>
                                        </ltv:QueryParameters> 
                                        <ltv:AdditionalParameters> 
                                          <ltv:Properties isActiveList='0'/> 
                                        </ltv:AdditionalParameters>";$result="m:ResultItemChannelLists"}
                                    ],
                                        
########## untested            
        "GetCurrentPlayback"    =>  [sub {$content='';},
                                        {"m:Locator" => sub {$hash->{helper}{lastchunk} = $_->text_only();},}
                                    ],
                                        
        "GetMediaEvent"         =>  [sub {$content='<MediaEventReference mediaEventUuid="'.$actPar1.'"/>';$result="m:ShortInfo"}],
            
        "GetChannelInfo"        =>  [sub {$content=""}],
            
        "GetCurrentEvent"       =>  [sub {$content="<ltv:Player>0</ltv:Player>";},
                                        {"m:Name" => sub {LoeweTV_PrepareReading($hash,"CurrentEvent_Name", $_->text("m:Name"));},
                                        "m:ExtendedInfo" => sub {LoeweTV_PrepareReading($hash,"CurrentEvent_Info",$_->text("m:ExtendedInfo"));},
                                        "m:Locator" => sub {LoeweTV_PrepareReading($hash,"CurrentEvent_Locator",$_->text("m:Locator"));}}
                                    ],
                                        
        "GetNextEvent"          => [sub {$content="<ltv:Player>0</ltv:Player>";},
                                        {"m:Name" => sub {LoeweTV_PrepareReading($hash,"NextEvent_Name", $_->text("m:Name"));},
                                        "m:ExtendedInfo" => sub {LoeweTV_PrepareReading($hash,"NextEvent_Info",$_->text("m:ExtendedInfo"));},
                                        "m:Locator" => sub {LoeweTV_PrepareReading($hash,"NextEvent_Locator",$_->text("m:Locator"));}}],
                                        
        "ZapToMedia"            => [sub { my $tpar=$actPar1; $tpar =~ s/&amp;/<>/g; $tpar =~ s/&/&amp;/g; $tpar =~ s/<>/&amp;/g; 
                                         $content="<ltv:Player>0</ltv:Player><ltv:Locator>".$tpar."</ltv:Locator>";},
                                        {"ltv:Result" => sub {$result="ltv:Result",$_->text("ltv:Result");}}],
            
        "SetActionField"        => [sub {$content="<ltv:InputText>".$actPar1."</ltv:InputText>";$result="m:Result"}],
            
        "GetDRPlusArchive"      => [sub {$content="<ltv:QueryParameters>
                                        <ltv:Range startIndex='".$actPar1."' maxItems='10'/>
                                        <ltv:OrderField field='userChannelNumber' type='ascending'/>
                                        </ltv:QueryParameters>";$result="ltv:ResultItemDRPlusFragment"}
                                    ],
    );

   Log3 $name, 5, "STARTING SENDREQUEST: $action";
   
   
   # ??? hash for params need to be moved to initialize
   
    my %hu_sr_params = (
                    url        => "http://".$hash->{HOST}.":905/loewe_tablet_0001",
                    timeout    => 30,
                    method     => "POST",
                    header     => "",
                    callback   => \&LoeweTV_HU_Callback
    );

    $hash->{HU_SR_PARAMS} = \%hu_sr_params;
    
    # create hash for storing readings for update
    my %hu_sr_readings = ();
    $hash->{HU_SR_PARAMS}->{SR_READINGS} = \%hu_sr_readings;
    
    #$action = "GetDeviceData" if( ! defined($action));
    
    my $xmlheader = "<?xml version='1.0' encoding='UTF-8'?>\n<env:Envelope
        xmlns:env=\"http://schemas.xmlsoap.org/soap/envelope/\"
        xmlns:ltv=\"urn:loewe.de:RemoteTV:Tablet\">\n<env:Body>\n";
    
    my $action_xml1 = "<ltv:$action>\n";
    
    my $xmlheader2 = "<ltv:fcid>".$hash->{FCID}."</ltv:fcid>
            <ltv:ClientId>".$hash->{CLIENTID}."</ltv:ClientId>\n";

    my $action_xml2 = "\n</ltv:$action>";
    
    my $footer = "\n</env:Body></env:Envelope>\n";
    

    if ($actions{$action}[0]) {
        $actions{$action}[0]->();
        $handlers=$actions{$action}[1];
    
    } else {
        print "Unknown action: $action\n";
    };

    # Aufbau der Messages
    $message = $xmlheader.$action_xml1.$xmlheader2.$content.$action_xml2.$footer;
  

    # construct the HTTP header
    
    # ??? move to global
    my $LoeweTV_header = "User-Agent: Assist Media/23 CFNetwork/808 Darwin/16.0.0\r\n".
      "Accept: */*\r\n".
      "Accept-Encoding: gzip, deflate\r\n".
      "Accept-Language: de-de\r\n".
      "Content-Type: application/soap+xml; charset=utf-8\r\n".
      "Connection: keep-alive";

    $hash->{HU_SR_PARAMS}->{header} = $LoeweTV_header.
      "\r\n"."SOAPAction: ".$action;

    $hash->{HU_SR_PARAMS}->{data} = $message;

    $hash->{HU_SR_PARAMS}->{action} = $action;

    $hash->{HU_SR_PARAMS}->{handlers} = $handlers;
  
    $hash->{HU_SR_PARAMS}->{hash} = $hash;

    Log3 $name, 5, "Sub LoeweTV_SendRequest ($name) - Action ".$actionString."   Request: ".Dumper($message);
    
    # send the request non blocking
    if ( defined( $ret ) ) {
      Log3 $name, 1, "LoeweTV_SendRequest $name: Failed with :$ret:";
      LoeweTV_HU_Callback( $hash->{HU_SR_PARAMS}, $ret, "");

    } else {
      $hash->{HU_DO_PARAMS}->{args} = \@args;
      
      Log3 $name, 4, "LoeweTV_SendRequest $name: call url :".$hash->{HU_SR_PARAMS}->{url}.": ";
      HttpUtils_NonblockingGet( $hash->{HU_SR_PARAMS} );

    }
}


#####################################
#  INTERNAL: Callback is the callback for any nonblocking call to the TV
#   3 params are defined for callbacks
#     param-hash
#     err
#     data (returned from url call)
# empty string used instead of undef for no return/err value
sub LoeweTV_HU_Callback($$$)
{
  my ( $param, $err, $data ) = @_;
  my $hash= $param->{hash};
  my $name = $hash->{NAME};

  my $ret;
  my $action = $param->{action};

  Log3 $name, 4, "LoeweTV_HU_Callback $name: ".
    (defined( $err )?"status err :".$err.":":"no error");
  Log3 $name, 5, "LoeweTV_HU_Callback $name:   data :".(( defined( $data ) )?$data:"<undefined>");

  if ( $err ne "" ) {
    $ret = "Error returned: $err";
    $hash->{lastresponse} = $ret;
  } elsif ( $param->{code} != 200 ) {
    $ret = "HTTP-Error returned: ".$param->{code};
    $hash->{lastresponse} = $ret;
  } else {
  
    my $handlers = $param->{handlers};
    my $twig2;
  
    Log3 $name, 2, "LoeweTV_HU_Callback $name: action: ".$action."   code : ".$param->{code};

    if ( ( defined($data) ) && ( $data ne "" ) ) {
      Log3 $name, 4, "LoeweTV_HU_Callback $name: handle XML values";
      $twig2 = XML::Twig->new(twig_handlers => $handlers,keep_encoding => 1)->parse($data);
    }
    
    $hash->{lastresponse} = $data;
    $ret = "SUCCESS";
  }

  # handle readings
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "requestAction", $action );   
  readingsBulkUpdate($hash, "requestResult", $ret );   
  
  if ( $ret eq  "SUCCESS" ) {
    Log3 $name, 4, "LoeweTV_HU_Callback $name: update readings";
    my $refreadings = $param->{SR_READINGS};
    foreach my $readName ( keys %$refreadings ) {
      Log3 $name, 5, "LoeweTV_HU_Callback $name: reading: ".$readName."   value :".$refreadings->{$readName}.":";
      if ( defined( $refreadings->{$readName} ) ) {
        readingsBulkUpdate($hash, $readName, $refreadings->{$readName} );        
      } else {
        CommandDeleteReading(undef,"$name $readName");
      }
    }
  }
  readingsEndUpdate($hash, 1);   
  
  # clean param hash
  delete( $param->{data} );
  delete( $param->{code} );
  
  $hash->{doStatus} = "";

  #########################
  # start next command in queue if available
  if ( ( defined( $hash->{actionQueue} ) ) && ( scalar( @{ $hash->{actionQueue} } ) ) ) {
    my $ref = shift @{ $hash->{actionQueue} };
    Log3 $name, 4, "LoeweTV_HU_Callback $name: handle queued cmd with :@$ref[0]: ";
    LoeweTV_SendRequest( $hash, @$ref[0], @$ref[1], @$ref[2] );
  }
  

}

    

#######################################################
############ Presence Erkennung Begin #################
#######################################################
sub LoeweTV_Presence($) {

    my $hash    = shift;    
    my $name    = $hash->{NAME};
    
    $hash->{helper}{RUNNING_PID} = BlockingCall("LoeweTV_PresenceRun", $name.'|'.$hash->{HOST}, "LoeweTV_PresenceDone", 5, "LoeweTV_PresenceAborted", $hash) unless(exists($hash->{helper}{RUNNING_PID}) );
}

sub LoeweTV_PresenceRun($) {

    my $string          = shift;
    my ($name, $host)   = split("\\|", $string);
    
    my $tmp;
    my $response;

    
    $tmp = qx(ping -c 3 -w 2 $host 2>&1);

    if(defined($tmp) and $tmp ne "") {
    
        chomp $tmp;
        Log3 $name, 5, "LoeweTV ($name) - ping command returned with output:\n$tmp";
        $response = "$name|".(($tmp =~ /\d+ [Bb]ytes (from|von)/ and not $tmp =~ /[Uu]nreachable/) ? "present" : "absent");
    
    } else {
    
        $response = "$name|Could not execute ping command";
    }
    
    Log3 $name, 4, "Sub LoeweTV_PresenceRun ($name) - Sub finish, Call LoeweTV_PresenceDone";
    return $response;
}

sub LoeweTV_PresenceDone($) {

    my ($string)            = @_;
    
    my ($name,$response)    = split("\\|",$string);
    my $hash                = $defs{$name};
    
    
    delete($hash->{helper}{RUNNING_PID});
    
    Log3 $name, 4, "Sub LoeweTV_PresenceDone ($name) - Der Helper ist disabled. Daher wird hier abgebrochen" if($hash->{helper}{DISABLED});
    return if($hash->{helper}{DISABLED});
    
    readingsSingleUpdate($hash,'presence',$response,1);
    
    Log3 $name, 4, "Sub LoeweTV_PresenceDone ($name) - Abschluss!";
}

sub LoeweTV_PresenceAborted($) {

    my ($hash)  = @_;
    my $name    = $hash->{NAME};

    
    delete($hash->{helper}{RUNNING_PID});
    readingsSingleUpdate($hash,'presence','timedout', 1);
    
    Log3 $name, 4, "Sub LoeweTV_PresenceAborted ($name) - The BlockingCall Process terminated unexpectedly. Timedout!";
}

####### Presence Erkennung Ende ############


#######################################################
############# HELPER   ################################
#######################################################
sub LoeweTV_IsPresent($) {
    my $hash = shift;
    return (ReadingsVal($hash->{NAME},'presence','absent') eq 'present');
}

sub LoeweTV_HasAccess($) {
    my $hash = shift;
    return (ReadingsVal($hash->{NAME},'access','undef') eq 'accepted');
}


#######################################################
############ Channellist functions    #################
#######################################################
# handle channel list
# call GetChannelList with listid
#   on ChannelListView --> get the list id --> remember in hash
#   on ResultItemFragment --> gain attributes --> sequenceNumber="9076679" totalResults="100" returnedResults="100" startIndex="0"
#       if start at 0 --> clean current table
#       if not complete --> queue next trunk startindex+100
#   on ResultItemReference --> queue GetMediaItems for uuid in mediaItemUuid

sub LoeweTV_hasChannelList($) {
    my ($hash)        = @_;
    return defined( $hash->{helper}{ChannelListView} );
}


sub LoeweTV_NewChannelList($$) {
    my ($hash,$channelist)        = @_;
    
    my $name                    = $hash->{NAME};
 
    Log3 $name, 4, "LoeweTV_NewChannelList $name: List: ".$channelist;
    
    # handle this only if there is a channellist id
    return if ((  ! defined( $channelist ) ) || ( $channelist eq "" ) );

    if ( $hash->{helper}{ChannelListView} ne $channelist ) {
      # delete current content if content returned
      delete( $hash->{helper}{ChannelList} );
      my %tmp = ();
      $hash->{helper}{ChannelList} = \%tmp;
      
      my @atmp = ();
      $hash->{helper}{ChannelSequence} = \@atmp;
      
      $hash->{helper}{ChannelListCount} = 0;
    }
    
    $hash->{helper}{ChannelListView} = $channelist;

}


sub LoeweTV_ChannelList_Reference($$) {
    my ($hash,$reference)  = @_;
    
    my $name                    = $hash->{NAME};
 
    Log3 $name, 4, "LoeweTV_ChannelList_Reference $name: Reference: ".$reference;
    
    LoeweTV_SendRequest($hash, 'GetMediaItem', $reference, "list" );
}

sub LoeweTV_ChannelList_Fragment($$$$$) {
    my ($hash,$sequence,$total,$returned,$start)  = @_;
    
    my $name                    = $hash->{NAME};
 
    Log3 $name, 4, "LoeweTV_ChannelList_Fragment $name: Sequence: ".$sequence."  Counts: ".$start."-".$returned."  (".$total.")";
    
    my $channelist = $hash->{helper}{ChannelListView};
    
    my $limit = AttrVal( $name, "maxchannel", 0 );
    
    $hash->{helper}{ChannelListCount} += $returned;
    
    return if ( ( $limit ) && ( $hash->{helper}{ChannelListCount} >= $limit ) );
    
    if ( $returned == 100 ) {
      Log3 $name, 4, "LoeweTV_ChannelList_Fragment $name: queue next request";
      # not yet complete queue the next request
      LoeweTV_SendRequest($hash, 'GetChannelList', $channelist, $start + $hash->{helper}{ChannelListCount} );
    }
    
}



sub LoeweTV_ChannelList_AddChannelXML($$$$$$) {
    my ($hash,$uuid, $locator, $caption, $shortinfo, $streamingurl)  = @_;
    
    my $name                    = $hash->{NAME};
 
    $uuid = $uuid->text_only() if ( defined( $uuid ) );
    $locator = $locator->text_only() if ( defined( $locator ) );
    $caption = $caption->text_only() if ( defined( $caption ) );
    $shortinfo = $shortinfo->text_only() if ( defined( $shortinfo ) );
    $streamingurl = $streamingurl->text_only() if ( defined( $streamingurl ) );
    
    Log3 $name, 2, "LoeweTV_ChannelList_AddChannel $name: DUPLICATE FOUND UUID: ".$uuid."  shortinfo: ".$shortinfo."   caption: ".$caption."  locator :".$locator."  streamingurl: ".$streamingurl.":";
    
    # no channellist ignore
    return undef if ( ! defined( $hash->{helper}{ChannelList} ) );
    
    if ( defined( $hash->{helper}{ChannelList}->{$uuid} ) ) {
      Log3 $name, 2, "LoeweTV_ChannelList_AddChannel $name: DUPLICATE FOUND UUID: ".$uuid."  shortinfo: ".$shortinfo."   caption: ".$caption."  locator :".$locator.":";
    }

    my @channel = ( $uuid, $locator, $caption, $shortinfo , $streamingurl );
    $hash->{helper}{ChannelList}->{$uuid} = \@channel;
    
    push( @{$hash->{helper}{ChannelSequence}}, $uuid );
    
}

sub LoeweTV_getAnElementForChannelUUID($$$) {
    my ($hash,$uuid, $element)        = @_;
    # no channellist ignore
    return undef if ( ! defined( $hash->{helper}{ChannelList} ) );
    
    my $channel = $hash->{helper}{ChannelList}->{$uuid};
    return undef if ( ! defined( $channel ) );

    return $$channel[$element];
}
    

sub LoeweTV_getNameForChannelUUID($$) {
    my ($hash,$uuid)        = @_;
    return LoeweTV_getAnElementForChannelUUID( $hash, $uuid, $LoeweTV_cl_shortinfo );
}
    
sub LoeweTV_getLocatorForChannelUUID($$) {
    my ($hash,$uuid)        = @_;
    return LoeweTV_getAnElementForChannelUUID( $hash, $uuid, $LoeweTV_cl_locator );
}
    
sub LoeweTV_getCaptionForChannelUUID($$) {
    my ($hash,$uuid)        = @_;
    return LoeweTV_getAnElementForChannelUUID( $hash, $uuid, $LoeweTV_cl_caption );
}
    
sub LoeweTV_findUUIDForChannelName($$) {
    my ($hash,$name)        = @_;
    # no channellist ignore
    return undef if ( ! defined( $hash->{helper}{ChannelList} ) );

    foreach my $uuid (keys %{$hash->{helper}{ChannelList}}) {
      my $aname = LoeweTV_getNameForChannelUUID( $hash, $uuid );
      return $uuid if ( $aname eq $name );
    }
    return undef;
}
    
sub LoeweTV_findUUIDForChannelLocator($$) {
    my ($hash,$locator)        = @_;
    # no channellist ignore
    return undef if ( ! defined( $hash->{helper}{ChannelList} ) );

    foreach my $uuid (keys %{$hash->{helper}{ChannelList}}) {
      my $alocator = LoeweTV_getLocatorForChannelUUID( $hash, $uuid );
      return $uuid if ( $alocator eq $locator );
    }
    return undef;
}
    
sub LoeweTV_findUUIDForChannelCaption($$) {
    my ($hash,$name)        = @_;
    # no channellist ignore
    return undef if ( ! defined( $hash->{helper}{ChannelList} ) );

    foreach my $uuid (keys %{$hash->{helper}{ChannelList}}) {
      my $aname = LoeweTV_getCaptionForChannelUUID( $hash, $uuid );
      return $uuid if ( $aname eq $name );
    }
    return undef;
}
    
sub LoeweTV_ChannelListText($) {
    my $hash        = shift;
    my $name        = $hash->{NAME};
    
    return "no channel list available" if ( ! defined( $hash->{helper}{ChannelList} ) );
    
    my $s = "ChannelList    - ".$hash->{helper}{ChannelListView}." - \r\r";
    
    my $num = 0;
    foreach my $uuid ( @{$hash->{helper}{ChannelSequence}} ) {
      my $channel = $hash->{helper}{ChannelList}->{$uuid};
      
      my $c = $$channel[$LoeweTV_cl_caption];
      $c = sprintf( "%4d", $c ) if ( $c =~ /\d+/ );
      
      $s .= $c."   ".$$channel[$LoeweTV_cl_shortinfo]." : ".$uuid."\r    ".$$channel[$LoeweTV_cl_locator]."\r    ".$$channel[$LoeweTV_cl_streamingurl]."\r";
      $num++
    }
    $s .= "\r Channel count ".$num."\r";
    
    return $s;
}

sub LoeweTV_GetChannelNames($$) {
    my ($hash,$split)        = @_;
    my $name        = $hash->{NAME};
    
    return "no channel list available" if ( ! defined( $hash->{helper}{ChannelList} ) );
    
    my $s = "";
    
    foreach my $uuid ( @{$hash->{helper}{ChannelSequence}} ) {
      my $name = LoeweTV_getNameForChannelUUID( $hash, $uuid );
      
      $s .= $split if ( length($s) > 0 );
      $s .= $name;
    }
    
    return $s;
}

sub LoeweTV_getTVMAC_setDEF($$) {

    my ($hash,$tvmac)   = @_;
    
    
    unless( defined($hash->{TVMAC}) ) {
    
        $hash->{TVMAC}  = $tvmac;
        $hash->{DEF} = "$hash->{HOST} $tvmac"
    }
}









#######################################################
1;

=pod
=item device
=item summary control for Loewe TV devices via network connection
=item summary_DE Steuerung von Loewe TV Ger&auml;ten &uuml;ber das Netzwerk
=begin html

<a name="LoeweTV"></a>
<h3>LoeweTV</h3>

=end html

=begin html_DE

<a name="LoeweTV"></a>
<h3>LoeweTV</h3>

=end html_DE

=cut
