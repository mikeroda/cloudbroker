#!/usr/bin/perl -w
###############################################################################
# Mike Roda    mike@mikeroda.com
###############################################################################
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
###############################################################################

=head1 NAME

VCL::Module::Provisioning::tmrk

=head1 SYNOPSIS

 VCL module to support Terremark vCloud Express API Provisioning

=head1 DESCRIPTION

 This module provides support for Terremark vCloud Express API 0.8a-ext1.6
 http://vcloudexpress.terremark.com/
 API documentation:
 https://community.vcloudexpress.terremark.com/en-us/product_docs/m/vcefiles/2342/download.aspx

=cut

##############################################################################
package VCL::Module::Provisioning::tmrk;

use FindBin;
use lib "$FindBin::Bin/../../..";

# Configure inheritance
use base qw(VCL::Module::Provisioning);

# Specify the version of this module
our $VERSION = '2.2.1';

# Specify the version of Perl to use
use 5.008000;

use strict;
use warnings;
use diagnostics;
use English qw( -no_match_vars );
use VCL::utils;

use HTTP::Request;
use HTTP::Request::Common;
use HTTP::Cookies;
use LWP::UserAgent;
use XML::LibXML;

our $cookie_jar;
our $ua;

##############################################################################

=head1 Local GLOBAL VARIABLES

=cut

use constant vCLOUD => 'https://services.vcloudexpress.terremark.com/api';
use constant vCLOUD_API => 'v0.8a-ext1.6';
use constant vCLOUD_RETRIES => 0;
use constant vCLOUD_NS => 'http://www.vmware.com/vcloud/v0.8';
use constant vCLOUD_KEY => '/etc/vcl/vcloud.pem';
use constant TIMEOUT_DEPLOY_MINS => 10;
use constant TIMEOUT_POWER_ON_MINS => 5;
use constant TIMEOUT_POWER_OFF_MINS => 5;
use constant POLLING_INTERVAL_SECS => 20;
use constant use_intantiation_params => 0;

##############################################################################

#///////////////////////////////////////////////////////////////////////////// 
=head2 initialize
        
 Parameters  : none
 Returns     : boolean
 Description : Initialized the VMware vCloud API object by logging in and 
               obtaining a token for subsequent calls. False is returned if a
               token cannot be obtained. 

=cut

sub initialize {
    my $self = shift;

	if (ref($self) !~ /tmrk/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
    
	$cookie_jar = HTTP::Cookies->new(
    file => "$ENV{'HOME'}/lwp_cookies.dat",
	    autosave => 1,
    	ignore_discard => 0,
	);

	$ua = LWP::UserAgent->new;
	$ua->cookie_jar($cookie_jar);

    my $response = $self->_login() || return;

	# get a link to the organization from the information returned from login
	my $org = $self->_xpath($response->content, '//ns:Org/@href', 1);
	if (!defined($org)) {
		return;
	}

	# get the organization information to obtain a link to the vDC
    my $req = HTTP::Request->new(GET => $org);
    $response = $self->_request($req);
	if (!defined($response)) {
		notify($ERRORS{'CRITICAL'}, 0, "Failed to get org: $org");
		return;
	}

	$self->{vDC} = $self->_xpath($response->content, '//ns:Link[@type=\'application/vnd.vmware.vcloud.vdc+xml\']/@href', 1);
	if (!defined($self->{vDC})) {
		return;
	}

    return 1;
}       

#///////////////////////////////////////////////////////////////////////////// 
=head2 _debug_http
        
 Parameters  : HTTP::Request, HTTP::Response
 Returns     : none
 Description : A shortcut for outputting errors from the REST server

=cut

# A shortcut for outputting errors form the REST server
sub _debug_http {
    my $self = shift;
	my $req = shift;
    my $response = shift;
    
	if (ref($self) !~ /tmrk/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
    
	notify($ERRORS{'DEBUG'}, 0, $req->as_string);
	notify($ERRORS{'DEBUG'}, 0, $response->content);
}

#///////////////////////////////////////////////////////////////////////////// 
=head2 _login
        
 Parameters  : none
 Returns     : HTTP::Response
 Description : Login to vCloud Express and get the cookie with the authentication token

=cut

sub _login()
{
	my $self = shift;

	if (ref($self) !~ /tmrk/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
    my $req = HTTP::Request->new(POST => vCLOUD.'/'.vCLOUD_API.'/login');
    $req->header('Content-Length' => 0);
    $req->authorization_basic($TMRK_USER, $TMRK_PASS);

	notify($ERRORS{'DEBUG'}, 0, "Login ".$TMRK_USER);
    my $response = $ua->request($req);
    if (!$response->is_success) {
		notify($ERRORS{'CRITICAL'}, 0, "Login failure");
        return;
    }

	notify($ERRORS{'OK'}, 0, "Login successful");

	$cookie_jar->save;

	return $response;
}

#///////////////////////////////////////////////////////////////////////////// 
=head2 _request
        
 Parameters  : HTTP::Request
 Returns     : HTTP::Response
 Description : Invoke a HTTP request and return the response, performing 
               automatic retries if necessary.

=cut

sub _request
{
	my $self = shift;
	my $req = shift;
	my ($response);

	if (ref($self) !~ /tmrk/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	for (my $count = 0; $count <= vCLOUD_RETRIES; $count++) {
	    $response = $ua->request($req);
	    if ($response->is_success) {
    	    return $response;
	    }
	    if ($response->content =~ m/401 \- Unauthorized/) {
	    	sleep(3);
			$ua->cookie_jar->clear;
			$self->_login;
	    }
	}
	
   	$self->_debug_http($req, $response);
   	return;
}

#///////////////////////////////////////////////////////////////////////////// 
=head2 versions
        
 Parameters  : none
 Returns     : none
 Description : Print available versions of the vCloud Express API.

=cut

sub versions
{
	my $self = shift;

	if (ref($self) !~ /tmrk/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}

	notify($ERRORS{'DEBUG'}, 0, "Getting API versions");
    my $response = $ua->request(GET vCLOUD.'/versions');

    if (!$response->is_success) {
        $self->_debug_http($response);
        return 0;
    }

	my $parser = XML::LibXML->new();
	my $doc = $parser->parse_string($response->content);

	my $xc = XML::LibXML::XPathContext->new( $doc->documentElement()  );
	$xc->registerNs('ns', 'http://www.vmware.com/vcloud/versions');

	my @n = $xc->findnodes('//ns:Version');
	foreach my $nod (@n) {
		my $version = $nod->textContent;
		notify($ERRORS{'OK'}, 0, "API version: $version");
   	}
      	
  	return 1;
}

#///////////////////////////////////////////////////////////////////////////// 
=head2 _xpath
        
 Parameters  : XML content, XPath string
 Returns     : String value
 Description : Find and return the value of a given Xpath in the XML content.

=cut

sub _xpath
{
	my $self = shift;
	my $content = shift;
	my $xpath = shift;
	my $debug = shift;
	my $ns = vCLOUD_NS;
	$ns = shift if @_;
	
	if (ref($self) !~ /tmrk/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}

	my $parser = XML::LibXML->new();
	my $doc = $parser->parse_string($content);

	my $xc = XML::LibXML::XPathContext->new( $doc->documentElement()  );
	$xc->registerNs('ns', $ns);
	my $value = $xc->findvalue($xpath);

	if ($debug && (!defined($value) || $value eq '')) {
		notify($ERRORS{'DEBUG'}, 0, "Cannot parse XPath: $xpath");
		notify($ERRORS{'DEBUG'}, 0, "$content");
		return;
	}
	
	return $value;	
}

sub _get_from_vdc
{
	my $self = shift;
	my $xpath = shift;
	my $debug = 1;
	$debug = shift if @_;

	if (ref($self) !~ /tmrk/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}

	
	notify($ERRORS{'DEBUG'}, 0, "Getting vDC");
    my $req = HTTP::Request->new(GET => $self->{vDC});
    my $response = $self->_request($req);
	if (!defined($response)) {
		notify($ERRORS{'CRITICAL'}, 0, "Failed to get vDC: ".$self->{vDC});
		return;
	}

    return $self->_xpath($response->content, $xpath, $debug);
}

#///////////////////////////////////////////////////////////////////////////// 
=head2 _create_vm
        
 Parameters  : none
 Returns     : none
 Description : Create a new Virtual Machine

=cut

sub _create_vm
{
	my $self = shift;
    my $vAppName = shift;
	my $vAppTemplate = shift;

	if (ref($self) !~ /tmrk/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}

	my $network = $self->_get_from_vdc('//ns:Network/@href');
	if (!defined($network)) {
		notify($ERRORS{'CRITICAL'}, 0, "unable to get Network from vDC");
		return;
	}
	
	my $doc = XML::LibXML->createDocument;
	my $root = $doc->createElementNS( vCLOUD_NS, "InstantiateVAppTemplateParams" );
	$root->setNamespace("http://www.w3.org/2001/XMLSchema-instance", "xsi", 0);
	$doc->setDocumentElement( $root );
	$root->setAttribute("name", $vAppName);

	my $VAppTemplate = XML::LibXML::Element->new( "VAppTemplate" );
	$VAppTemplate->setAttribute("href", $vAppTemplate);
	$root->addChild($VAppTemplate);

	my $InstantiationParams;
	
	if (use_intantiation_params) {
		$InstantiationParams = XML::LibXML::Element->new( "InstantiationParams" );
		$root->addChild($InstantiationParams);
	
		my $ProductSection = XML::LibXML::Element->new( "ProductSection" );
		$ProductSection->setNamespace("http://www.vmware.com/vcloud/v0.8", "q1", 0);
		$ProductSection->setNamespace("http://schemas.dmtf.org/ovf/envelope/1", "ovf", 0);
		$InstantiationParams->addChild($ProductSection);
	
		my $Property = XML::LibXML::Element->new( "Property" );
		$Property->setNamespace("http://schemas.dmtf.org/ovf/envelope/1");
		$Property->setAttribute("ovf:key", "row");
		$Property->setAttribute("ovf:value", "Api");
		$ProductSection->addChild($Property);
	
		$Property = XML::LibXML::Element->new( "Property" );
		$Property->setNamespace("http://schemas.dmtf.org/ovf/envelope/1");
		$Property->setAttribute("ovf:key", "group");
		$Property->setAttribute("ovf:value", "Api");
		$ProductSection->addChild($Property);

		$Property = XML::LibXML::Element->new( "Property" );
		$Property->setNamespace("http://schemas.dmtf.org/ovf/envelope/1");
		$Property->setAttribute("ovf:key", "sshKeyFingerprint");
		$Property->setAttribute("ovf:value", "e4:b3:18:b3:0e:11:44:ef:2d:2b:44:ef:58:09:b5:8e");
		$ProductSection->addChild($Property);
	}
	
	my $vHardwareSection = XML::LibXML::Element->new( "VirtualHardwareSection" );
	if (defined($InstantiationParams)) {
		$InstantiationParams->addChild($vHardwareSection);
	}
	else {
		$root->addChild($vHardwareSection);
	}

	my $item = XML::LibXML::Element->new( "Item" );
	$item->setNamespace("http://schemas.dmtf.org/ovf/envelope/1");
	$vHardwareSection->addChild($item);

	my $instanceID = XML::LibXML::Element->new( "InstanceID" );
	$instanceID->setNamespace("http://schemas.dmtf.org/wbem/wscim/1/cimschema/2/CIM_ResourceAllocationSettingData");
	$instanceID->appendText("1");
	$item->addChild($instanceID);

	my $resourceType = XML::LibXML::Element->new( "ResourceType" );
	$resourceType->setNamespace("http://schemas.dmtf.org/wbem/wscim/1/cimschema/2/CIM_ResourceAllocationSettingData");
	$resourceType->appendText("3");
	$item->addChild($resourceType);

	my $virtualQuantity = XML::LibXML::Element->new( "VirtualQuantity" );
	$virtualQuantity->setNamespace("http://schemas.dmtf.org/wbem/wscim/1/cimschema/2/CIM_ResourceAllocationSettingData");
	$virtualQuantity->appendText("1");
	$item->addChild($virtualQuantity);

	$item = XML::LibXML::Element->new( "Item" );
	$item->setNamespace("http://schemas.dmtf.org/ovf/envelope/1");
	$vHardwareSection->addChild($item);

	$instanceID = XML::LibXML::Element->new( "InstanceID" );
	$instanceID->setNamespace("http://schemas.dmtf.org/wbem/wscim/1/cimschema/2/CIM_ResourceAllocationSettingData");
	$instanceID->appendText("2");
	$item->addChild($instanceID);

	$resourceType = XML::LibXML::Element->new( "ResourceType" );
	$resourceType->setNamespace("http://schemas.dmtf.org/wbem/wscim/1/cimschema/2/CIM_ResourceAllocationSettingData");
	$resourceType->appendText("4");
	$item->addChild($resourceType);

	$virtualQuantity = XML::LibXML::Element->new( "VirtualQuantity" );
	$virtualQuantity->setNamespace("http://schemas.dmtf.org/wbem/wscim/1/cimschema/2/CIM_ResourceAllocationSettingData");
	$virtualQuantity->appendText("512");
	$item->addChild($virtualQuantity);

	my $networkConfigSection = XML::LibXML::Element->new( "NetworkConfigSection" );
	if (defined($InstantiationParams)) {
		$InstantiationParams->addChild($networkConfigSection);
	}
	else {
		$root->addChild($vHardwareSection);
	}
	my $networkConfig = XML::LibXML::Element->new( "NetworkConfig" );
	$networkConfigSection->addChild($networkConfig);
	my $networkAssociation = XML::LibXML::Element->new( "NetworkAssociation" );
	$networkAssociation->setAttribute("href", $network);
	$networkConfig->addChild($networkAssociation);

    my $req = HTTP::Request->new(POST => $self->{vDC}.'/action/instantiatevAppTemplate');
    $req->header('Content-Length' => length($doc->toString));
    $req->header('Content-Type' => 'application/vnd.vmware.vcloud.instantiateVAppTemplateParams+xml');
    $req->content($doc->toString);

	notify($ERRORS{'DEBUG'}, 0, "Creating VM $vAppName");
	my $response = $self->_request($req);
	if (!defined($response)) {
		notify($ERRORS{'CRITICAL'}, 0, "Failed to create VM $vAppName");
		return;
	}

    #
	# This is what the response should look like 
	# 
	# <VApp href="https://services.vcloudexpress.terremark.com/api/v0.8/vapp/430879" type="application/vnd.vmware.vcloud.vApp+xml" name="MyApplication" status="1" size="10" xmlns="http://www.vmware.com/vcloud/v0.8" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
	#   <Link rel="up" href="https://services.vcloudexpress.terremark.com/api/v0.8/vdc/3068" type="application/vnd.vmware.vcloud.vdc+xml"/>
	# </VApp>

	notify($ERRORS{'DEBUG'}, 0, "VM $vAppName is being deployed");
    sleep(30);

	$self->{vApp} = $self->_xpath($response->content, '//ns:VApp/@href', 1);
	if (!defined($self->{vApp})) {
		return;
	}

	my $status;
	for (my $count = 0; $count <= TIMEOUT_DEPLOY_MINS * (60 / POLLING_INTERVAL_SECS); $count++) {
		$req = HTTP::Request->new(GET => $self->{vApp});
    	$response = $self->_request($req);
		if (!defined($response)) {
			notify($ERRORS{'CRITICAL'}, 0, "Failed to get vApp: ".$self->{vApp});
			return;
		}

		$status = $self->_xpath($response->content, '//ns:VApp/@status', 1);
		if (!defined($status)) {
			return;
		}

		if ($status eq '0' || $status eq '1') {
		    sleep(POLLING_INTERVAL_SECS);
		}
		else {
			last;
		}
	}
	
	if ($status ne '2' && $status ne '3') {
		notify($ERRORS{'CRITICAL'}, 0, "VM failed to deploy");
		return;
	}
	
	notify($ERRORS{'OK'}, 0, "VM $vAppName successfully deployed");
	
	return 1;
}

#///////////////////////////////////////////////////////////////////////////// 
=head2 _delete_vm
        
 Parameters  : URL to the vApp
 Returns     : none
 Description : Delete an existing Virtual Machine

=cut

sub _delete_vm
{
	my $self = shift;
    my $vAppName = shift;
    my $vApp = shift;

	if (ref($self) !~ /tmrk/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}

    my $req = HTTP::Request->new(DELETE => $vApp);

	notify($ERRORS{'DEBUG'}, 0, "Deleting VM $vAppName");
	my $response = $self->_request($req);
	if (!defined($response)) {
		notify($ERRORS{'CRITICAL'}, 0, "Failed to delete VM $vAppName");
		return;
	}

	my $status;
	for (my $count = 0; $count <= TIMEOUT_DEPLOY_MINS * (60 / POLLING_INTERVAL_SECS); $count++) {
		$req = HTTP::Request->new(GET => $vApp);
    	$response = $self->_request($req);
		if (!defined($response)) {
			notify($ERRORS{'OK'}, 0, "VM $vAppName successfully deleted");
			return 1;
		}

		sleep(POLLING_INTERVAL_SECS);
	}
	
	notify($ERRORS{'WARNING'}, 0, "Timed out waiting for VM $vAppName to delete");

	return;
}

sub _connect_to_internet
{
	my $self = shift;
	my $port = shift;

	if (ref($self) !~ /tmrk/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}

	my $internetServices = $self->_get_from_vdc('//ns:Link[@name=\'Internet Services\']/@href');
	if (!defined($internetServices)) {
		notify($ERRORS{'CRITICAL'}, 0, "Unable to get Internet Services from vDC");
		return;
	}

	# build the xml document to open up a TCP port on a new public IP address
	my $doc = XML::LibXML->createDocument;
	my $root = $doc->createElementNS( "urn:tmrk:vCloudExpressExtensions-1.6", "CreateInternetServiceRequest" );
	$doc->setDocumentElement( $root );
	my $element = XML::LibXML::Element->new( "Name" );
	$element->appendText("TCP Internet Service");
	$root->addChild($element);
	$element = XML::LibXML::Element->new( "Protocol" );
	$element->appendText("TCP");
	$root->addChild($element);
	$element = XML::LibXML::Element->new( "Port" );
	$element->appendText($port);
	$root->addChild($element);
	$element = XML::LibXML::Element->new( "Enabled" );
	$element->appendText("true");
	$root->addChild($element);

    my $req = HTTP::Request->new(POST => $internetServices);
    $req->header('Content-Length' => length($doc->toString));
    $req->header('Content-Type' => 'application/vnd.vmware.vcloud.createInternetService+xml');
    $req->content($doc->toString);
 
	notify($ERRORS{'DEBUG'}, 0, "Creating Internet service on TCP port $port");
    my $response = $self->_request($req);
	if (!defined($response)) {
		notify($ERRORS{'CRITICAL'}, 0, "Failed to create Internet service");
		return;
	}

	# get a link to the internet service we just created and save the public IP address
	my $InternetService = $self->_xpath($response->content, '//ns:InternetService/ns:Href', 1, 'urn:tmrk:vCloudExpressExtensions-1.6');
	if (!defined($InternetService)) {
		return;
	}

	$self->{PublicIpAddress} = $self->_xpath($response->content, '//ns:PublicIpAddress/ns:Name', 1, 'urn:tmrk:vCloudExpressExtensions-1.6');
	if (!defined($self->{PublicIpAddress})) {
		return;
	}
	notify($ERRORS{'DEBUG'}, 0, "Public IP address is: ".$self->{PublicIpAddress});

	# build the xml request to create a node service which will tie the internet service to the VM
	$doc = XML::LibXML->createDocument;
	$root = $doc->createElementNS( "urn:tmrk:vCloudExpressExtensions-1.6", "CreateNodeServiceRequest" );
	$doc->setDocumentElement( $root );
	$element = XML::LibXML::Element->new( "IpAddress" );
	$element->appendText($self->{IpAddress});
	$root->addChild($element);
	$element = XML::LibXML::Element->new( "Name" );
	$element->appendText("My Node Service");
	$root->addChild($element);
	$element = XML::LibXML::Element->new( "Port" );
	$element->appendText($port);
	$root->addChild($element);
	$element = XML::LibXML::Element->new( "Enabled" );
	$element->appendText("true");
	$root->addChild($element);

    $req = HTTP::Request->new(POST => $InternetService."/nodeServices");
    $req->header('Content-Length' => length($doc->toString));
    $req->header('Content-Type' => 'application/vnd.vmware.vcloud.createInternetService+xml');
    $req->content($doc->toString);
 
	notify($ERRORS{'DEBUG'}, 0, "Creating node service for private IP ".$self->{IpAddress}." on TCP port $port");
    $response = $self->_request($req);
	if (!defined($response)) {
		notify($ERRORS{'CRITICAL'}, 0, "Failed to create node service");
		return;
	}

	notify($ERRORS{'OK'}, 0, "IP ".$self->{PublicIpAddress}." successfully linked to ".$self->{IpAddress}." on TCP port $port");
	
	return 1;
}

sub _disconnect_from_internet
{
	my $self = shift;

	if (ref($self) !~ /tmrk/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}

	my $vAppName = shift;
	my $vApp = shift;

	notify($ERRORS{'DEBUG'}, 0, "Disconnecting VM $vAppName from internet service");

	# get the private IP address of the VM
	notify($ERRORS{'DEBUG'}, 0, "Getting IP Address of existing VM $vAppName");
	my $req = HTTP::Request->new(GET => $vApp);
   	my $response = $self->_request($req);
	if (!defined($response)) {
		notify($ERRORS{'CRITICAL'}, 0, "Failed to get vApp: $vApp");
		return;
	}
	my $ipAddress = $self->_xpath($response->content, '//ns:NetworkConnection/ns:IpAddress', 1);
	if (!defined($ipAddress)) {
		return;
	}

	notify($ERRORS{'DEBUG'}, 0, "VM $vAppName has IP address $ipAddress");

	my $internetServices = $self->_get_from_vdc('//ns:Link[@name=\'Internet Services\']/@href');
	if (!defined($internetServices)) {
		notify($ERRORS{'CRITICAL'}, 0, "Unable to get Internet Services from vDC");
		return;
	}

	notify($ERRORS{'DEBUG'}, 0, "Getting all internet services");
    $req = HTTP::Request->new(GET => $internetServices);
    $response = $self->_request($req);
	if (!defined($response)) {
		notify($ERRORS{'CRITICAL'}, 0, "Failed to get internet services");
		return;
	}

	my $parser = XML::LibXML->new();
	my $doc = $parser->parse_string($response->content);

	my $xc = XML::LibXML::XPathContext->new( $doc->documentElement()  );
	$xc->registerNs('ns', 'urn:tmrk:vCloudExpressExtensions-1.6');

	my @nodes = $xc->findnodes('//ns:InternetService/ns:Href');
	foreach my $internetService (@nodes) {
		my $xc_is = XML::LibXML::XPathContext->new( $internetService );
		$xc_is->registerNs('ns', 'urn:tmrk:vCloudExpressExtensions-1.6');
		my $id = $xc_is->findvalue('//ns:InternetService/ns:Id');
		my $url = $xc_is->findvalue('//ns:InternetService/ns:Href');
		my $PublicIpAddress = $xc_is->findvalue('//ns:PublicIpAddress/ns:Name');
		my $PublicIpId = $xc_is->findvalue('//ns:PublicIpAddress/ns:Id');

		notify($ERRORS{'DEBUG'}, 0, "Getting nodes on internet service $id");

	    my $req = HTTP::Request->new(GET => $url."/nodeServices");
	    my $response = $self->_request($req);
		if (!defined($response)) {
			notify($ERRORS{'CRITICAL'}, 0, "Failed to get: ".$url."/nodeServices");
			return;
		}

		my $nodeIpAddress = $self->_xpath($response->content, '//ns:IpAddress', 1, 'urn:tmrk:vCloudExpressExtensions-1.6');
		my $nodeService = $self->_xpath($response->content, '//ns:Href', 1, 'urn:tmrk:vCloudExpressExtensions-1.6');
		my $nodeId = $self->_xpath($response->content, '//ns:Id', 1, 'urn:tmrk:vCloudExpressExtensions-1.6');

  		if ($nodeIpAddress eq $ipAddress) {
			notify($ERRORS{'DEBUG'}, 0, "Deleting node service $nodeId");
		    $req = HTTP::Request->new(DELETE => $nodeService);
    		$response = $self->_request($req);
			if (!defined($response)) {
				notify($ERRORS{'CRITICAL'}, 0, "Failed to delete node service: $nodeService");
				return;
			}
		    sleep(15);
			notify($ERRORS{'DEBUG'}, 0, "Successfully deleted node service $nodeId");

			notify($ERRORS{'DEBUG'}, 0, "Deleting internet service on IP $PublicIpAddress");
		    $req = HTTP::Request->new(DELETE => $url);
    		$response = $self->_request($req);
			if (!defined($response)) {
				notify($ERRORS{'CRITICAL'}, 0, "Failed to delete internet service: $url");
				return;
			}
		    sleep(15);
			notify($ERRORS{'DEBUG'}, 0, "Successfully deleted internet service $id");

			notify($ERRORS{'DEBUG'}, 0, "Releasing public IP $PublicIpAddress");
		    $req = HTTP::Request->new(DELETE => vCLOUD.'/extensions/v1.6/publicIp/'.$PublicIpId);
	   		$response = $self->_request($req);
			if (!defined($response)) {
				notify($ERRORS{'WARNING'}, 0, "Failed to release public IP: $PublicIpId");
				return;
			}
			notify($ERRORS{'DEBUG'}, 0, "Successfully released public IP $PublicIpAddress");

  			return 1;
  		}
   	}

	return;
}

sub _is_connected_internet
{
	my $self = shift;

	if (ref($self) !~ /tmrk/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}

    if (!$self->{IpAddress}) {
		notify($ERRORS{'CRITICAL'}, 0, "Private IP address of VM is not known");
		return;
    }

	my $internetServices = $self->_get_from_vdc('//ns:Link[@name=\'Internet Services\']/@href');
	if (!defined($internetServices)) {
		notify($ERRORS{'CRITICAL'}, 0, "Unable to get Internet Services from vDC");
		return;
	}

	notify($ERRORS{'DEBUG'}, 0, "Getting all internet services");
    my $req = HTTP::Request->new(GET => $internetServices);
    my $response = $self->_request($req);
	if (!defined($response)) {
		notify($ERRORS{'CRITICAL'}, 0, "Failed to get internet services");
		return;
	}

	my $parser = XML::LibXML->new();
	my $doc = $parser->parse_string($response->content);

	my $xc = XML::LibXML::XPathContext->new( $doc->documentElement()  );
	$xc->registerNs('ns', 'urn:tmrk:vCloudExpressExtensions-1.6');

	my @nodes = $xc->findnodes('//ns:InternetService/ns:Href');
	foreach my $internetService (@nodes) {
		my $xc_is = XML::LibXML::XPathContext->new( $internetService );
		$xc_is->registerNs('ns', 'urn:tmrk:vCloudExpressExtensions-1.6');
		my $id = $xc_is->findvalue('//ns:InternetService/ns:Id');
		my $url = $xc_is->findvalue('//ns:InternetService/ns:Href');
		my $PublicIpAddress = $xc_is->findvalue('//ns:PublicIpAddress/ns:Name');

		notify($ERRORS{'DEBUG'}, 0, "Getting nodes on internet service $id");

	    my $req = HTTP::Request->new(GET => $url."/nodeServices");
	    my $response = $self->_request($req);
		if (!defined($response)) {
			notify($ERRORS{'CRITICAL'}, 0, "Failed to get: ".$url."/nodeServices");
			return;
		}

		my $IpAddress = $self->_xpath($response->content, '//ns:IpAddress', 1, 'urn:tmrk:vCloudExpressExtensions-1.6');

  		if ($IpAddress eq $self->{IpAddress}) {
  			$self->{PublicIpAddress} = $PublicIpAddress;
  			return 1;
  		}
   	}

	return;
}

#///////////////////////////////////////////////////////////////////////////// 
=head2 power_on
        
 Parameters  : none
 Returns     : none
 Description : Power-on a Virtual Machine

=cut

sub power_on
{
	my $self = shift;

	if (ref($self) !~ /tmrk/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}

    my $vAppName = shift;
	my $vApp = shift;
	
	notify($ERRORS{'DEBUG'}, 0, "Powering up VM $vAppName");
	my $req = HTTP::Request->new(POST => $vApp.'/power/action/powerOn');
    $req->header('Content-Length' => 0);
   	my $response = $self->_request($req);
	if (!defined($response)) {
		notify($ERRORS{'CRITICAL'}, 0, "Failed to issue power-on command");
		return;
	}

    sleep(30);
    my $status;
	for (my $count = 0; $count <= TIMEOUT_POWER_ON_MINS * (60 / POLLING_INTERVAL_SECS); $count++) {
		$req = HTTP::Request->new(GET => $vApp);
    	$response = $self->_request($req);
		if (!defined($response)) {
			notify($ERRORS{'CRITICAL'}, 0, "Failed to get vApp: $vApp");
			return;
		}

		$status = $self->_xpath($response->content, '//ns:VApp/@status', 1);
		if (!defined($status)) {
			return;
		}

		if ($status ne '4') {
		    sleep(POLLING_INTERVAL_SECS);
		}
		else {
			last;
		}
	}

	if ($status ne '4') {
		notify($ERRORS{'CRITICAL'}, 0, "VM $vAppName failed to power");
		return;
	}

	notify($ERRORS{'OK'}, 0, "VM $vAppName successfully powered up");

	return 1;
}

#///////////////////////////////////////////////////////////////////////////// 
=head2 power_off
        
 Parameters  : none
 Returns     : none
 Description : Power-off a Virtual Machine

=cut

sub power_off
{
	my $self = shift;

	if (ref($self) !~ /tmrk/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}

    my $vAppName = shift;
	my $vApp = shift;
	
	notify($ERRORS{'DEBUG'}, 0, "Powering down VM $vAppName");
	my $req = HTTP::Request->new(POST => $vApp.'/power/action/powerOff');
    $req->header('Content-Length' => 0);
   	my $response = $self->_request($req);
	if (!defined($response)) {
		notify($ERRORS{'CRITICAL'}, 0, "Failed to power-off VM $vAppName");
		return;
	}

    sleep(30);
    my $status;
	for (my $count = 0; $count <= TIMEOUT_POWER_OFF_MINS * (60 / POLLING_INTERVAL_SECS); $count++) {
		$req = HTTP::Request->new(GET => $vApp);
    	$response = $self->_request($req);
		if (!defined($response)) {
			notify($ERRORS{'CRITICAL'}, 0, "Failed to get vApp: ".$vApp);
			return;
		}

		$status = $self->_xpath($response->content, '//ns:VApp/@status', 1);
		if (!defined($status)) {
			return;
		}
		
		if ($status ne '2') {
		    sleep(POLLING_INTERVAL_SECS);
		}
		else {
			last;
		}
	}
	
	if ($status ne '2') {
		notify($ERRORS{'CRITICAL'}, 0, "VM $vAppName failed to power off");
		return;
	}

	notify($ERRORS{'OK'}, 0, "VM $vAppName successfully powered down");
	
	return 1;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 does_image_exist

 Parameters  : none
 Returns     : 0 or 1
 Description : Searches the catalog for requested image
               returns 1 if found or 0 if not

=cut

sub does_image_exist
{
	my $self = shift;

	if (ref($self) !~ /tmrk/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}

	my $image_name = $self->data->get_image_prettyname();

	my $vapp_template = $self->_get_vapp_template($image_name);
	if (!defined($vapp_template)) {
		return;
	}
	
	notify($ERRORS{'OK'}, 0, "The Image $image_name exists");

	return 1;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 _get_vapp_template

 Parameters  : none
 Returns     : URL to the vAppTemplate
 Description : Searches the catalog for requested image

=cut

sub _get_vapp_template
{
	my $self = shift;

	if (ref($self) !~ /tmrk/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}

	my $image_name = shift;

	my $catalog = $self->_get_from_vdc('//ns:Link[@type=\'application/vnd.vmware.vcloud.catalog+xml\']/@href');
	if (!defined($catalog)) {
		notify($ERRORS{'CRITICAL'}, 0, "Unable to get catalog from vDC");
		return;
	}
	
	notify($ERRORS{'DEBUG'}, 0, "Getting catalog of images");
    my $req = HTTP::Request->new(GET => $catalog);
    my $response = $self->_request($req);
	if (!defined($response)) {
		notify($ERRORS{'CRITICAL'}, 0, "Failed to get catalog of images");
		return;
	}

	my $catalogItem = $self->_xpath($response->content, '//ns:CatalogItem[@name=\''.$image_name.'\']/@href', 1);
	if (!$catalogItem) {
        notify($ERRORS{'CRITICAL'}, 0, "Image $image_name not found in catalog");
        return;
	}

	notify($ERRORS{'DEBUG'}, 0, "Getting catalog item $image_name");
    $req = HTTP::Request->new(GET => $catalogItem);
    $response = $self->_request($req);
	if (!$response) {
        notify($ERRORS{'CRITICAL'}, 0, "Failed to get catalog item $image_name");
        return;
	}

	return $self->_xpath($response->content, '//ns:Entity[@type=\'application/vnd.vmware.vcloud.vAppTemplate+xml\']/@href', 1);
}

sub _get_template_desc
{
	my $self = shift;
	my $vAppTemplate = shift;

	if (ref($self) !~ /tmrk/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}
	
	notify($ERRORS{'DEBUG'}, 0, "Getting template description");
    my $req = HTTP::Request->new(GET => $vAppTemplate);
    my $response = $self->_request($req);
	if (!defined($response)) {
		notify($ERRORS{'CRITICAL'}, 0, "Failed to get template description");
		return;
	}

	my $description = $self->_xpath($response->content, '//ns:Description', 1);
	if (!defined($description)) {
		return;
	}

	notify($ERRORS{'OK'}, 0, "$description");
}

#///////////////////////////////////////////////////////////////////////////// 
=head2 load
        
 Parameters  : vAppName
 Returns     : 1 if successful, 0 if error
 Description : Load a new Virtual Machine 

=cut

sub load
{
	my $self = shift;
	my $request_id            = $self->data->get_request_id();
	my $reservation_id        = $self->data->get_reservation_id();
	my $computer_id           = $self->data->get_computer_id();
	my $computer_shortname    = $self->data->get_computer_short_name;
	my $image_name            = $self->data->get_image_prettyname;
	my $laststate_name        = $self->data->get_request_laststate_name;

	if (ref($self) !~ /tmrk/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return;
	}

	# Look to see if the vApp already exists
	my $vApp = $self->_get_from_vdc('//ns:ResourceEntity[@type=\'application/vnd.vmware.vcloud.vApp+xml\' and @name=\''.$computer_shortname.'\']/@href', 0);
	if ($vApp) {
		# power down the VM first, if necessary
		$self->power_off($computer_shortname, $vApp);
		
		# disconnect it from the internet
		$self->_disconnect_from_internet($computer_shortname, $vApp);
		
		# create the VM
		if (!$self->_delete_vm($computer_shortname, $vApp)) {
			return;
		}
	}

	if ($laststate_name ne "new") {
		notify($ERRORS{'OK'}, 0, "Last state is $laststate_name; not a new reservation, skipping actual load");
		return 1;
	}

	# get the image template
	my $vAppTemplate = $self->_get_vapp_template($image_name);

	# create the VM
	$self->_create_vm($computer_shortname, $vAppTemplate);
		
	# should be able to find the vApp now
	$vApp = $self->_get_from_vdc('//ns:ResourceEntity[@type=\'application/vnd.vmware.vcloud.vApp+xml\' and @name=\''.$computer_shortname.'\']/@href');
	if (!defined($vApp)) {
		notify($ERRORS{'CRITICAL'}, 0, "could not get vApp after creating VM");
		return;
	}
	
	# get the status and private IP address of the VM
	notify($ERRORS{'DEBUG'}, 0, "Getting details on existing vApp: $vApp");
	my $req = HTTP::Request->new(GET => $vApp);
   	my $response = $self->_request($req);
	if (!defined($response)) {
		notify($ERRORS{'CRITICAL'}, 0, "Failed to get vApp: $vApp");
		return;
	}

	my $status = $self->_xpath($response->content, '//ns:VApp/@status', 1);
	if (!defined($status)) {
		return;
	}
		
	$self->{IpAddress} = $self->_xpath($response->content, '//ns:NetworkConnection/ns:IpAddress', 1);
	if (!defined($self->{IpAddress})) {
		return;
	}
	
	if ($status eq "2") {
		return if (!$self->power_on($computer_shortname, $vApp));
	}

	if (!$self->_is_connected_internet) {
		return if (!$self->_connect_to_internet(22));
	}

	notify($ERRORS{'DEBUG'}, 0, "Removing old hosts entry");
	my $sedoutput = `sed -i "/.*\\b$computer_shortname\$/d" /etc/hosts`;
	notify($ERRORS{'DEBUG'}, 0, $sedoutput);

	# Add new entry to /etc/hosts for $computer_shortname
	#
	# TO-DO: should be using the Private IP here but VCL won't be able to reach
	# the host on the private IP unless the Cisco VPN agent is running
	#
	`echo -e $self->{PublicIpAddress}"\t$computer_shortname" >> /etc/hosts`;

	# Set IP info
	if (update_computer_address($computer_id, $self->{PublicIpAddress})) {
		notify($ERRORS{'DEBUG'}, 0, "$computer_shortname has public IP ".$self->{PublicIpAddress});
	}
	else {
		notify($ERRORS{'CRITICAL'}, 0, "could not update address for $computer_shortname");
		return;
	}

	notify($ERRORS{'OK'}, 0, "VM $computer_shortname is loaded with $image_name");

	return 1;
}

#/////////////////////////////////////////////////////////////////////////

=head2 node_status

 Parameters  : $nodename, $log
 Returns     : array of related status checks
 Description : checks on sshd, currentimage

=cut

sub node_status {
	my $self = shift;

	my $requestedimagename = 0;
	my $image_os_type      = 0;
	my $computer_shortname = 0;
	my $identity_keys      = vCLOUD_KEY;
	my $log                = 0;
	my $computer_node_name = 0;

	# Check if subroutine was called as a class method
	if (ref($self) !~ /tmrk/i) {
		notify($ERRORS{'OK'}, 0, "subroutine was called as a function");
		if (ref($self) eq 'HASH') {
			$log = $self->{logfile};
			#notify($ERRORS{'DEBUG'}, $log, "self is a hash reference");

			$requestedimagename = $self->{imagerevision}->{imagename};
			$image_os_type      = $self->{image}->{OS}->{type};
			$computer_node_name = $self->{computer}->{hostname};

		} ## end if (ref($self) eq 'HASH')
		    # Check if node_status returned an array ref
		elsif (ref($self) eq 'ARRAY') {
			notify($ERRORS{'DEBUG'}, $log, "self is a array reference");
		}

		$computer_shortname = $1 if ($computer_node_name =~ /([-_a-zA-Z0-9]*)(\.?)/);
	}
	else {

		# try to contact vm
		# $self->data->get_request_data;
		# get state of vm
		$requestedimagename = $self->data->get_image_name;
		$image_os_type      = $self->data->get_image_os_type;
		$computer_shortname = $self->data->get_computer_short_name;
	}

	notify($ERRORS{'OK'},    0, "Entering node_status, checking status of $computer_shortname");
	notify($ERRORS{'DEBUG'}, 0, "requeseted image name: $requestedimagename");

	my ($hostnode);

	# Create a hash to store status components
	my %status;

	# Initialize all hash keys here to make sure they're defined
	$status{status}       = 0;
	$status{currentimage} = 0;
	$status{ping}         = 0;
	$status{ssh}          = 0;
	$status{image_match}  = 0;

	# Check if node is pingable
	notify($ERRORS{'DEBUG'}, 0, "checking if $computer_shortname is pingable");
	if (_pingnode($computer_shortname)) {
		$status{ping} = 1;
		notify($ERRORS{'OK'}, 0, "$computer_shortname is pingable ($status{ping})");
	}
	else {
		notify($ERRORS{'OK'}, 0, "$computer_shortname is not pingable ($status{ping})");
		return $status{status};
	}

	notify($ERRORS{'DEBUG'}, 0, "Trying to ssh...");

	#can I ssh into it
	my $sshd = _sshd_status($computer_shortname, $requestedimagename, $image_os_type);

	#is it running the requested image
	if ($sshd eq "on") {
		$status{ssh} = 1;

		notify($ERRORS{'DEBUG'}, 0, "SSH good, trying to query image name");

		############################################
		# TO-DO: NEED TO GET CURRENT IMAGE FROM API
		############################################
		$status{currentimage} = $requestedimagename;

		notify($ERRORS{'DEBUG'}, 0, "Image name: $status{currentimage}");

		if ($status{currentimage}) {
			chomp($status{currentimage});
			if ($status{currentimage} =~ /$requestedimagename/) {
				$status{image_match} = 1;
				notify($ERRORS{'OK'}, 0, "$computer_shortname is loaded with requestedimagename $requestedimagename");
			}
			else {
				notify($ERRORS{'OK'}, 0, "$computer_shortname reports current image is currentimage= $status{currentimage} requestedimagename= $requestedimagename");
			}
		} ## end if ($status{currentimage})
	} ## end if ($sshd eq "on")

	# Determine the overall machine status based on the individual status results
	if ($status{ssh} && $status{image_match}) {
		$status{status} = 'READY';
	}
	else {
		$status{status} = 'RELOAD';
	}

	notify($ERRORS{'DEBUG'}, 0, "status set to $status{status}");

	notify($ERRORS{'DEBUG'}, 0, "returning node status hash reference (\$node_status->{status}=$status{status})");
	return \%status;

} ## end sub node_status

1;
