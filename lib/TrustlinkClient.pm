package TrustlinkClient;

use warnings;
use strict;

use File::Basename;
use File::stat;
use URI;
use IO::File;
use Socket;
use Data::Dumper;
use List::MoreUtils qw/any/;

=head1 NAME

TrustlinkClient - Perl links inserter from trustlink.ru.

=cut

our $VERSION = 'T0.3.4';


=head1 SYNOPSIS

Coming soon.

=cut

our (
	$TRUSTLINK_USER
);

sub new
{
	my $class = shift;
	return bless {
		'tl_tpath'             => dirname(__FILE__),
		'_inited'              => undef,
		'_links_loaded'        => undef,
		'_options'             => shift() || undef,
	}, $class;
}

sub init {
	my $self    = shift;
	my %_init = (
		'tl_verbose'           => 0,
		'tl_debug'             => 1,
		'tl_isrobot'           => 0,
		'tl_test'              => 0,
		'tl_test_count'        => 4,
		'tl_template'          => 'template',
		'tl_charset'           => 'DEFAULT',
		'tl_use_ssl'           => 0,
		'tl_server'            => 'db.trustlink.ru',
		'tl_cache_lifetime'    => 21600,
		'tl_cache_reloadtime'  => 3600,
		'tl_links_db_file'     => '',
		'tl_error'             => [],
		'tl_links'             => {},
		'tl_links_page'        => [],
		'tl_host'              => '',
		'tl_request_uri'       => '',
		'tl_socket_timeout'    => 6,
		'tl_force_show_code'   => 0,
		'tl_multi_site'        => 0,
		'tl_is_static'         => 0,
		'tl_tpath'             => dirname(__FILE__),
		'remote_addr'          => $ENV{REMOTE_ADDR}||'',
		'_inited'              => undef,
		'_links_loaded'        => undef,
		@_,
	);
	foreach my $key ( keys %_init) {
		$self->{$key} //= delete $_init{$key};
	}
	my $options = delete $self->{_options};

	if (ref($options) eq "HASH")
	{
		$self->{tl_host} = $options->{host} if($options->{host} ne '');
	}
	elsif(ref($options) ne '')
	{
		$self->{tl_host} = $options if($options ne '');
		$options = {};
	}
	$self->{tl_host} = $ENV{HTTP_HOST} if($self->{tl_host} eq '');

	$self->{tl_host} =~ s/^www\.//;
	$self->{tl_host} = lc($self->{tl_host});
	

	$self->{tl_tpath}             = $options->{tpath}   || $self->{tl_tpath};
	$self->{tl_charset}           = $options->{charset} || $self->{tl_charset};
	$self->{tl_is_static}         = 1 if $options->{is_static};
	$self->{tl_multi_site}        = 1 if $options->{multi_site};
	$self->{tl_verbose}           = 1 if ($options->{verbose} || $self->{tl_links}->{__trustlink_debug__});
	$self->{tl_force_show_code}   = 1 if ($options->{force_show_code} || $self->{tl_links}->{__trustlink_debug__});
	$self->{tl_socket_timeout}    = $options->{socket_timeout} if (($options->{socket_timeout} || '') =~ /^\d+$/ && $options->{socket_timeout} > 0);

	if ($options->{request_uri}) 
	{
		$self->{tl_request_uri} = $options->{request_uri};
	}
	else
	{
		if ($self->{tl_is_static})
		{
			$self->{tl_request_uri} = $ENV{REQUEST_URI} || '/';
			$self->{tl_request_uri} =~ s/\?.*$//;
			$self->{tl_request_uri} =~ s/\/+/\//;
		}
		else
		{
			$self->{tl_request_uri} = $ENV{REQUEST_URI} || '/';
		}
	}
	$self->{tl_request_uri} = $self->rawurldecode($self->{tl_request_uri});


	$TRUSTLINK_USER = $options->{TRUSTLINK_USER};
	
	$self->raise_error("Parametr TRUSTLINK_USER is not defined.") if($TRUSTLINK_USER eq '');
	
	if (($ENV{HTTP_TRUSTLINK}||'') eq $TRUSTLINK_USER)
	{
		$self->{tl_test}    = 1;
		$self->{tl_isrobot} = 1;
		$self->{tl_verbose} = 1;
	}
	$self->{_inited} = 1;

	return $self;
}

sub load_links
{
	my $self = shift;
	$self->{_inited} or $self->init();

	if ($self->{tl_multi_site} == 1)
	{
		$self->{tl_links_db_file} = $self->{tl_tpath} . '/trustlink.' . $self->{tl_host} . '.links.db';
	}
	else
	{
		$self->{tl_links_db_file} = $self->{tl_tpath} . '/trustlink.links.db';
	}

	my $_creat = !-f $self->{tl_links_db_file};
	if (!-f $self->{tl_links_db_file})
	{
		my $SYSOPEN_MODE = O_WRONLY|O_CREAT|O_NONBLOCK|O_NOCTTY;

		sysopen my $fh, $self->{tl_links_db_file} ,$SYSOPEN_MODE or $self->raise_error("Can't create $self->{tl_links_db_file} : $!");
		close $fh or $self->raise_error("Can't close $self->{tl_links_db_file} : $!");
		chmod (0666, $self->{tl_links_db_file}) or $self->raise_error("Can't set permission to $self->{tl_links_db_file} : $!");
	}

	if (!-w $self->{tl_links_db_file})
	{
		$self->raise_error("There is no permissions to write: " . $self->{tl_links_db_file} . "! Set mode to 777 on the folder.");
	}


	my $sb = stat($self->{tl_links_db_file}) or $self->raise_error("Could not stat file: $self->{tl_links_db_file} ($!)");
	my $atime = $sb->atime if($sb);
	my $mtime = $sb->mtime if($sb);
	my $size = $sb->size if($sb);

	my $links;
	my $path = '/' . $TRUSTLINK_USER . '/' . lc( $self->{tl_host} ) . '/' . uc( $self->{tl_charset}).'.text';

	if ($mtime < (time()-$self->{tl_cache_lifetime}) || ($mtime < (time()-$self->{tl_cache_reloadtime}) && !$size) || $_creat)
	{
		$self->lc_write($self->{tl_links_db_file}, '');
		$links = $self->fetch_remote_file($self->{tl_server}, $path);

		if ($links ne "")
		{
			if (substr($links, 0, 12) eq 'FATAL ERROR:')
			{
				if($self->{tl_debug}){
					$self->raise_error($links);
				}
			}
			else
			{
				$self->lc_write($self->{tl_links_db_file}, $links);
			}
		}
	}

	$links = $self->lc_read($self->{tl_links_db_file}, $self->{tl_request_uri});

	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=gmtime($mtime);
	$self->{tl_file_change_date} = sprintf("%02d.%02d.%02d %02d:%02d:%02d", $mday, $mon+1, $year+1900, $hour,$min, $sec);
	($atime, $mtime,  $sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = (); # Очищаем память от данных

	$self->{tl_file_size} = length($links);

	unless($links)
	{
        $self->{tl_links} = {};
        if ($self->{tl_debug} == 1)
        {
        	$self->raise_error("Empty file.");
        }
	}
	elsif (ref($links) ne "HASH")
	{
		$self->{tl_links} = {};
		if ($self->{tl_debug} == 1)
		{
			$self->raise_error("Can't readed data from file.");
		}
    }
    elsif(ref($links) eq "HASH")
    {
    	$self->{tl_links} = $links;
    }

    if ($self->{tl_links}->{__trustlink_delimiter__} ne "")
    {
        $self->{tl_links_delimiter} = $self->{tl_links}->{__trustlink_delimiter__};
    }

	if ($self->{tl_test})
	{
		if (ref($self->{tl_links}->{__test_tl_link__}) eq "HASH")
		{
			for (my $i=0;$i < $self->{tl_test_count}; $i++)
			{
				push @{$self->{tl_links_page}}, $self->{tl_links}->{__test_tl_link__};
			}
		}
	}
	else
	{
		my $tmp = {};
		foreach my $key (keys %{$self->{tl_links}})
		{
			$tmp->{$self->rawurldecode($key)} = $self->{tl_links}->{$key};
		}
		$self->{tl_links} = $tmp;
		undef($tmp);

		if ($self->{tl_links}->{$self->{tl_request_uri}} ne "")
		{
			$self->{tl_links_page} = $self->{tl_links}->{$self->{tl_request_uri}};
		}
	}
	$self->{tl_links_count} = scalar @{$self->{tl_links_page}};
	$self->{_links_loaded} = 1;
}

sub fetch_remote_file
{
	my $self = shift;
	$self->{_inited} or $self->init();
	my ($host, $path) = @_;
	my $port="80";

	my $user_agent = "Trustlink Client PERL $VERSION";

	socket(SOCK, PF_INET, SOCK_STREAM, getprotobyname('tcp'));
	my $paddr = sockaddr_in($port, inet_aton($host));

	connect(SOCK, $paddr);
	send (SOCK, "GET $path HTTP/1.0\nHOST:$host\nUSER-AGENT:$user_agent\n\n", 0);

	my @data=<SOCK>;
	close(SOCK);
	my $buff = join('', @data);

	if($buff ne "")
	{
		my @page = split("\r\n\r\n", $buff);
		return $page[1];
	}
	$self->raise_error("Can't connect to server: " . $host . $path);
	return;
}

sub lc_read
{
	my $self = shift;
	$self->{_inited} or $self->init();
	my $filename = shift;
	my $request_uri = shift;

	my $buffer;

	open(FILE, $filename) or $self->raise_error("Can't get data from the file: $filename ($!)");
	
	if(lc($self->{tl_charset}) eq "utf-8")
	{
		binmode(FILE,':utf8');
	}
	else
	{
		binmode(FILE);
	}

	sysread(FILE, $buffer,-s FILE);
	close(FILE);

	if($filename =~ /\.db$/)
	{
		my $buf = {};
		$buffer =~ s|\r||igms;

		my ($test_tl_link) = ($buffer =~ m|^__test_tl_link__:(.*?)\n\n|imsg);
		$buffer =~ s|^__test_tl_link__:(.*?)\n\n||imsg;
		$test_tl_link = {($test_tl_link =~ m|^(.*?):(.*?)$|imsg)};

		my $match = {($buffer =~ m|^__([a-z_]*)__:(.*?)\n|imsg)};
		$match->{trustlink_robots} = [ split(/ <break> /, $match->{trustlink_robots}) ];
		$match->{test_tl_link} = $test_tl_link; 

		for my $key (keys(%$match))
		{
			$buf->{'__'.$key.'__'} = $match->{$key};
		}
		my $ruri = $request_uri;
		$ruri =~ s/\?/\\?/;
		
		
		my ($cur_links) = ($buffer =~ m|^$ruri/?:(.*?)\n\n|imsg);
		my @cur = map(trim($_), split(/ <break> /, $cur_links));
		for my $link (@cur)
		{
			push @{$buf->{$request_uri}}, {$link =~ m|^(.*?):(.*?)$|imsg};
		}
		return $buf;
	}
	return $buffer;
}

sub lc_write
{
	my $self = shift;
	$self->{_inited} or $self->init();
	my $filename = shift;
	my $content = shift;
	my $hash = shift;

	open(FILE, ">$filename") or die "$!";
	binmode(FILE);
	print FILE $content  or die "$!";
	close(FILE);
}


sub raise_error
{
	my $self = shift;
	$self->{_inited} or $self->init();
	push @{$self->{tl_error}}, shift;
}

sub build_links
{
	my $self = shift;
	$self->{_links_loaded} or $self->load_links();
	my $links = $self->{tl_links_page};
	my $result ='';


	if ($self->{tl_links}->{__trustlink_start__} ne '' && ((any{ $_ eq $self->{remote_addr} } @{$self->{tl_links}->{__trustlink_robots__}} ) || $self->{tl_force_show_code}))
	{
		$result .= $self->{tl_links}->{__trustlink_start__};
	}

	if ((any{ $_ eq $self->{remote_addr} } @{$self->{tl_links}->{__trustlink_robots__}}) || $self->{tl_verbose})
	{
		$result .= '<!--REQUEST_URI=' . $ENV{REQUEST_URI} . "-->\n";
		$result .= "\n<!--\n";
		$result .= "L $VERSION\n";
		$result .= 'REMOTE_ADDR=' . $self->{remote_addr} . "\n";
		$result .= 'request_uri=' . $self->{tl_request_uri} . "\n";
		$result .= 'charset=' . $self->{tl_charset} . "\n";
		$result .= 'is_static=' . $self->{tl_is_static} . "\n";
		$result .= 'multi_site=' . $self->{tl_multi_site} . "\n";
		$result .= 'file change date=' . $self->{tl_file_change_date} . "\n";
		$result .= 'lc_file_size=' . $self->{tl_file_size} . "\n";
		$result .= 'lc_links_count=' . $self->{tl_links_count} . "\n";
		$result .= 'left_links_count=' . $self->{tl_links_count} . "\n";
		$result .= '-->';
	}

	my $tpl_filename = $self->{tl_tpath}.'/'.$self->{tl_template}.".tpl.html";
	my $tpl = $self->lc_read($tpl_filename);

	$self->raise_error("Template file not found") unless($tpl);

	my @block = ($tpl =~ m/(<{block}>(.+)<{\/block}>)/is);
	unless($block[0])
	{
		$self->raise_error("Wrong template format: no <{block}><{/block}> tags");
	}
	else
	{
		$tpl =~ s/$block[0]/%s/;
		my $blockT = substr($block[0], 9, -10);

		if ($blockT !~ /<{head_block}>/)
		{
			$self->raise_error("Wrong template format: no <{head_block}> tag.");
		}
		if ($blockT !~ /<{\/head_block}>/)
		{
			$self->raise_error("Wrong template format: no <{/head_block}> tag.");
		}

		if ($blockT !~ /<{link}>/)
		{
			$self->raise_error("Wrong template format: no <{link}> tag.");
		}
		if ($blockT !~ /<{text}>/)
		{
			$self->raise_error("Wrong template format: no <{text}> tag.");
		}
		if ($blockT !~ /<{host}>/)
		{
			$self->raise_error("Wrong template format: no <{host}> tag.");
		}

		my $text;
		foreach my $link (@$links)
		{
			if (ref($link) ne "HASH")
			{
				$self->raise_error("link must be an array");
			}
			elsif ($link->{url} eq "" || $link->{text} eq "")
			{
				$self->raise_error("format of link must be an hash('anchor'=>\$anchor,'url'=>\$url,'text'=>\$text)");
			}
			else
			{
				my $host = lc(URI->new($link->{url})->host);
				if(!$host)
				{
					$self->raise_error("wrong format of url: ".$link->{url});
				}
				else
				{
					my $level = scalar($host =~ m/\./);

					if ($level < 1)
					{
						$self->raise_error("wrong host: $host in url $link->{url}");
					}
					else
					{
						my $a = $blockT;
						$host =~ s/^www\.//;
						$a =~ s/<{text}>/$link->{text}/;
						$a =~ s/<{host}>/$host/;

						if ($link->{anchor} eq "")
						{
							$a =~ s/<{head_block}>(.+)<{\/head_block}>//is;
						}
						else
						{
                			my $href = $link->{punicode_url} eq "" ? $link->{url} : $link->{punicode_url};
                			$a =~ s/<{link}>/<a href='$href'>$link->{anchor}<\/a>/;   
							$a =~ s/<{head_block}>//is;
							$a =~ s/<{\/head_block}>//is;
						}
						$text .= $a;
					}
				}
			}
		
		}
		if (ref($links) eq "ARRAY" && scalar @$links > 0)
		{
			$tpl = sprintf($tpl, $text);
			$result .= $tpl;
		}
	}
	if ($self->{tl_links}->{__trustlink_end__} ne '' && ((any {$_ eq $self->{remote_addr}} @{$self->{tl_links}->{__trustlink_robots__}}) || $self->{tl_force_show_code}))
	{
		$result .= $self->{tl_links}->{__trustlink_end__};
	}

	if ($self->{tl_test} == 1 && $self->{tl_isrobot} != 1)
	{
		$result = '<noindex>'.$result.'</noindex>';
	}

	# Вывод ошибок деал тут потому что они вообще не выводились никак
	if (scalar @{$self->{tl_error}} > 0 && $self->{tl_debug} == 1)
	{
		$result .= "\n<!-- ERRORS:\n";
		foreach(@{$self->{tl_error}})
		{
			$result .= $_."\n";
		}
		$result .= "-->";
	}

	return $result;
}

sub var_dump
{
	my $pr = Dumper(@_);
	$pr =~ s/</&lt;/ig;
	
	#print "<pre>".$pr."</pre>";
	raise_error($pr);
}

sub rawurldecode
{
	my $self = shift;
	my $s = shift;
	$s =~ s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg;
	return $s;
}

sub trim
{
	my $string = shift;
	return ltrim(rtrim( $string ));
}
sub ltrim 
{
	my $string = shift;
	$string =~ s/^\s+//;
	return $string;
}
sub rtrim
{
	my $string = shift;
	$string =~ s/\s+$//;
	return $string;
}

=head1 SEE ALSO

Coming soon...

=head1 AUTHOR

Dmitriy V. Simonov, C<< <dsimonov at gmail.com> >>

=head1 ACKNOWLEDGEMENTS

Thanks to TrustLink.ru

=head1 COPYRIGHT & LICENSE

Copyright 2010 Dmitriy V. Simonov.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

=cut

1; # End of TrustlinkClient
