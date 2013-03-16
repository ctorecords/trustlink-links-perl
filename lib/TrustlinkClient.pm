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

our $VERSION = '0.01';


=head1 SYNOPSIS

Coming soon.

=cut

our (
	$TRUSTLINK_USER
);

sub new
{
	my $class = shift;
	my $options = shift;
	my $this = {
		'tl_version'           => 'T0.3.4',
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
	};
	bless ($this, $class);

	if (ref($options) eq "HASH")
	{
		$this->{tl_host} = $options->{host} if($options->{host} ne '');
	}
	elsif(ref($options) ne '')
	{
		$this->{tl_host} = $options if($options ne '');
		$options = {};
	}
	$this->{tl_host} = $ENV{HTTP_HOST} if($this->{tl_host} eq '');

	$this->{tl_host} =~ s/^www\.//;
	$this->{tl_host} = lc($this->{tl_host});
	

	$this->{tl_tpath}             = $options->{tpath}   || $this->{tl_tpath};
	$this->{tl_charset}           = $options->{charset} || $this->{tl_charset};
	$this->{tl_is_static}         = 1 if $options->{is_static};
	$this->{tl_multi_site}        = 1 if $options->{multi_site};
	$this->{tl_verbose}           = 1 if ($options->{verbose} || $this->{tl_links}->{__trustlink_debug__});
	$this->{tl_force_show_code}   = 1 if ($options->{force_show_code} || $this->{tl_links}->{__trustlink_debug__});
	$this->{tl_socket_timeout}    = $options->{socket_timeout} if (($options->{socket_timeout} || '') =~ /^\d+$/ && $options->{socket_timeout} > 0);

	if ($options->{request_uri} ne '') 
	{
		$this->{tl_request_uri} = $options->{request_uri};
	}
	else
	{
		if ($this->{tl_is_static})
		{
			$this->{tl_request_uri} = $ENV{REQUEST_URI};
			$this->{tl_request_uri} =~ s/\?.*$//;
			$this->{tl_request_uri} =~ s/\/+/\//;
		}
		else
		{
			$this->{tl_request_uri} = $ENV{REQUEST_URI};
		}
	}
	$this->{tl_request_uri} = &rawurldecode($this->{tl_request_uri});


	$TRUSTLINK_USER = $options->{TRUSTLINK_USER};
	
	$this->raise_error("Parametr TRUSTLINK_USER is not defined.") if($TRUSTLINK_USER eq '');
	
	if (($ENV{HTTP_TRUSTLINK}||'') eq $TRUSTLINK_USER)
	{
		$this->{tl_test}    = 1;
		$this->{tl_isrobot} = 1;
		$this->{tl_verbose} = 1;
	}

	$this->load_links();
	return $this;
}

sub load_links
{
	my $this = shift;

	if ($this->{tl_multi_site} == 1)
	{
		$this->{tl_links_db_file} = $this->{tl_tpath} . '/trustlink.' . $this->{tl_host} . '.links.db';
	}
	else
	{
		$this->{tl_links_db_file} = $this->{tl_tpath} . '/trustlink.links.db';
	}

	my $_creat = !-f $this->{tl_links_db_file};
	if (!-f $this->{tl_links_db_file})
	{
		my $SYSOPEN_MODE = O_WRONLY|O_CREAT|O_NONBLOCK|O_NOCTTY;

		sysopen my $fh, $this->{tl_links_db_file} ,$SYSOPEN_MODE or $this->raise_error("Can't create $this->{tl_links_db_file} : $!");
		close $fh or $this->raise_error("Can't close $this->{tl_links_db_file} : $!");
		chmod (0666, $this->{tl_links_db_file}) or $this->raise_error("Can't set permission to $this->{tl_links_db_file} : $!");
	}

	if (!-w $this->{tl_links_db_file})
	{
		$this->raise_error("There is no permissions to write: " . $this->{tl_links_db_file} . "! Set mode to 777 on the folder.");
	}


	my $sb = stat($this->{tl_links_db_file}) or $this->raise_error("Could not stat file: $this->{tl_links_db_file} ($!)");
	my $atime = $sb->atime if($sb);
	my $mtime = $sb->mtime if($sb);
	my $size = $sb->size if($sb);

	my $links;
	my $path = '/' . $TRUSTLINK_USER . '/' . lc( $this->{tl_host} ) . '/' . uc( $this->{tl_charset}).'.text';

	if ($mtime < (time()-$this->{tl_cache_lifetime}) || ($mtime < (time()-$this->{tl_cache_reloadtime}) && !$size) || $_creat)
	{
		$this->lc_write($this->{tl_links_db_file}, '');
		$links = $this->fetch_remote_file($this->{tl_server}, $path);

		if ($links ne "")
		{
			if (substr($links, 0, 12) eq 'FATAL ERROR:')
			{
				if($this->{tl_debug}){
					$this->raise_error($links);
				}
			}
			else
			{
				$this->lc_write($this->{tl_links_db_file}, $links);
			}
		}
	}

	$links = $this->lc_read($this->{tl_links_db_file}, $this->{tl_request_uri});

	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=gmtime($mtime);
	$this->{tl_file_change_date} = sprintf("%02d.%02d.%02d %02d:%02d:%02d", $mday, $mon+1, $year+1900, $hour,$min, $sec);
	($atime, $mtime,  $sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = (); # Очищаем память от данных

	$this->{tl_file_size} = length($links);

	unless($links)
	{
        $this->{tl_links} = {};
        if ($this->{tl_debug} == 1)
        {
        	$this->raise_error("Empty file.");
        }
	}
	elsif (ref($links) ne "HASH")
	{
		$this->{tl_links} = {};
		if ($this->{tl_debug} == 1)
		{
			$this->raise_error("Can't readed data from file.");
		}
    }
    elsif(ref($links) eq "HASH")
    {
    	$this->{tl_links} = $links;
    }

    if ($this->{tl_links}->{__trustlink_delimiter__} ne "")
    {
        $this->{tl_links_delimiter} = $this->{tl_links}->{__trustlink_delimiter__};
    }

	if ($this->{tl_test})
	{
		if (ref($this->{tl_links}->{__test_tl_link__}) eq "HASH")
		{
			for (my $i=0;$i < $this->{tl_test_count}; $i++)
			{
				push @{$this->{tl_links_page}}, $this->{tl_links}->{__test_tl_link__};
			}
		}
	}
	else
	{
		my $tmp = {};
		foreach my $key (keys %{$this->{tl_links}})
		{
			$tmp->{rawurldecode($key)} = $this->{tl_links}->{$key};
		}
		$this->{tl_links} = $tmp;
		undef($tmp);

		if ($this->{tl_links}->{$this->{tl_request_uri}} ne "")
		{
			$this->{tl_links_page} = $this->{tl_links}->{$this->{tl_request_uri}};
		}
	}
	$this->{tl_links_count} = scalar @{$this->{tl_links_page}};
}

sub fetch_remote_file
{
	my $this = shift;
	my ($host, $path) = @_;
	my $port="80";

	my $user_agent = 'Trustlink Client PERL ' . $this->{tl_version};

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
	$this->raise_error("Can't connect to server: " . $host . $path);
	return;
}

sub lc_read
{
	my $this = shift;
	my $filename = shift;
	my $request_uri = shift;

	my $buffer;

	open(FILE, $filename) or $this->raise_error("Can't get data from the file: $filename ($!)");
	
	if(lc($this->{tl_charset}) eq "utf-8")
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
	my $this = shift;
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
	my $this = shift;
	push @{$this->{tl_error}}, shift;
}

sub build_links
{
	my $this = shift;
	my $links = $this->{tl_links_page};
	my $result ='';


	if ($this->{tl_links}->{__trustlink_start__} ne '' && ((any{ $_ eq $this->{remote_addr} } @{$this->{tl_links}->{__trustlink_robots__}} ) || $this->{tl_force_show_code}))
	{
		$result .= $this->{tl_links}->{__trustlink_start__};
	}

	if ((any{ $_ eq $this->{remote_addr} } @{$this->{tl_links}->{__trustlink_robots__}}) || $this->{tl_verbose})
	{
		$result .= '<!--REQUEST_URI=' . $ENV{REQUEST_URI} . "-->\n";
		$result .= "\n<!--\n";
		$result .= 'L ' . $this->{tl_version} . "\n";
		$result .= 'REMOTE_ADDR=' . $this->{remote_addr} . "\n";
		$result .= 'request_uri=' . $this->{tl_request_uri} . "\n";
		$result .= 'charset=' . $this->{tl_charset} . "\n";
		$result .= 'is_static=' . $this->{tl_is_static} . "\n";
		$result .= 'multi_site=' . $this->{tl_multi_site} . "\n";
		$result .= 'file change date=' . $this->{tl_file_change_date} . "\n";
		$result .= 'lc_file_size=' . $this->{tl_file_size} . "\n";
		$result .= 'lc_links_count=' . $this->{tl_links_count} . "\n";
		$result .= 'left_links_count=' . $this->{tl_links_count} . "\n";
		$result .= '-->';
	}

	my $tpl_filename = $this->{tl_tpath}.'/'.$this->{tl_template}.".tpl.html";
	my $tpl = $this->lc_read($tpl_filename);

	$this->raise_error("Template file not found") unless($tpl);

	my @block = ($tpl =~ m/(<{block}>(.+)<{\/block}>)/is);
	unless($block[0])
	{
		$this->raise_error("Wrong template format: no <{block}><{/block}> tags");
	}
	else
	{
		$tpl =~ s/$block[0]/%s/;
		my $blockT = substr($block[0], 9, -10);

		if ($blockT !~ /<{head_block}>/)
		{
			$this->raise_error("Wrong template format: no <{head_block}> tag.");
		}
		if ($blockT !~ /<{\/head_block}>/)
		{
			$this->raise_error("Wrong template format: no <{/head_block}> tag.");
		}

		if ($blockT !~ /<{link}>/)
		{
			$this->raise_error("Wrong template format: no <{link}> tag.");
		}
		if ($blockT !~ /<{text}>/)
		{
			$this->raise_error("Wrong template format: no <{text}> tag.");
		}
		if ($blockT !~ /<{host}>/)
		{
			$this->raise_error("Wrong template format: no <{host}> tag.");
		}

		my $text;
		foreach my $link (@$links)
		{
			if (ref($link) ne "HASH")
			{
				$this->raise_error("link must be an array");
			}
			elsif ($link->{url} eq "" || $link->{text} eq "")
			{
				$this->raise_error("format of link must be an hash('anchor'=>\$anchor,'url'=>\$url,'text'=>\$text)");
			}
			else
			{
				my $host = lc(URI->new($link->{url})->host);
				if(!$host)
				{
					$this->raise_error("wrong format of url: ".$link->{url});
				}
				else
				{
					my $level = scalar($host =~ m/\./);

					if ($level < 1)
					{
						$this->raise_error("wrong host: $host in url $link->{url}");
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
	if ($this->{tl_links}->{__trustlink_end__} ne '' && ((any {$_ eq $this->{remote_addr}} @{$this->{tl_links}->{__trustlink_robots__}}) || $this->{tl_force_show_code}))
	{
		$result .= $this->{tl_links}->{__trustlink_end__};
	}

	if ($this->{tl_test} == 1 && $this->{tl_isrobot} != 1)
	{
		$result = '<noindex>'.$result.'</noindex>';
	}

	# Вывод ошибок деал тут потому что они вообще не выводились никак
	if (scalar @{$this->{tl_error}} > 0 && $this->{tl_debug} == 1)
	{
		$result .= "\n<!-- ERRORS:\n";
		foreach(@{$this->{tl_error}})
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
