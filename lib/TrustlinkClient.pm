package TrustlinkClient;

use warnings;
use strict;


use URI::Escape;
use LWP::UserAgent::WithCache;
use File::Basename;
use URI;

=head1 NAME

TrustlinkClient - Perl links inserter from trustlink.ru.

=cut

our $VERSION = 'T0.4.0';

=head1 SYNOPSIS

Coming soon.

=cut


# эта переменная может задаваться в параметрах конструктора, либо как $TrustlinkClient::TRUSTLINK_USER вне модуля, либо через $ENV{TRUSTLINK_USER}

our $TRUSTLINK_USER;

# new конструктор
# параметрами могут быть переданы
#    либо строка - имя хоста,   TrustlinkClient->new('kirovka.ru');
#    либо ссылка на хэш с опциями, перекрываюшими опции по умолчанию  TrustlinkClient->new( { host => 'kirovka.ru', TRUSTLINK_USER => '213213214134' } );
sub new {
	my $class   = shift;
	my $options = shift;
	
	my $self = bless { _links_loaded => undef,
			   remote_addr   => $ENV{REMOTE_ADDR} || '0.0.0.0',
			   errors        => [],      # здесь копим строки ошибок
			   tl_links      => {},      # здесь хранятся все распарсенные ссылки, не знаю почему оно в параметрах
			   tl_links_page => [],      # здесь хранятся все ссылки предназначенные для вывода, не знаю почему оно в параметрах
		         }, $class;

	# параметры по умолчанию. Каждый может быть перекрыт аргументами конструктора
	my %_defaults = (
		'cache_lifetime'    => 21600,                     # удаляем файлы кеша старше чем это время 
		'cache_reloadtime'  => 3600,                      # берём данные из кеша если он свежее этого времени
		'charset'           => 'DEFAULT',                 # кодировка, в которой запрашиваем данные от трастлинка
		'debug'             => 1,                         # режим отладки
		'force_show_code'   => 0,                         # обрамляем вывод кодом взятым от трастлинка 
		'host'              => $ENV{HTTP_HOST} || '',     # наш хост
		'is_static'         => 0,                         # если да, то будет неизменяемый request_uri
		'is_robot'          => 0,                         # робот ли мы?
		'multi_site'        => 0,                         # WTF?
		'request_uri'       => '',                        # request_uri пришедший к нам
		'server'            => 'http://db.trustlink.ru',  # сервер трастлинка, откуда забираем данные 
		'socket_timeout'    => 6,                         # WTF?
		'template'          => 'template',                # имя шаблона к которому будет добавлен cуффикс .tpl.html'
		'test'              => 0,                         # режим тестирования
		'test_count'        => 4,                         # столько ссылок вставляем на страницу если мы в режиме тестирования
		'tpath'             => dirname(__FILE__),         # путь, где находится шаблон
		'cache_path'        => undef,                     # путь, где будет храниться кеш. Если undef, то где-то в /tmp
		'use_ssl'           => 0,                         # WTF?
		'verbose'           => 1,                         # будем ли многословны
	);
	
	$options = $options ? { host => $options } : { } if not 'HASH' eq ref $options; # это если в параметрах строка - имя хоста

	$self->{"tl_$_"} = $options->{$_} // $_defaults{$_} for keys %_defaults;  # перекрываем опции по умолчанию переданными в аргуметах конструктору

	$TRUSTLINK_USER = $options->{TRUSTLINK_USER} if exists $options->{TRUSTLINK_USER};  # явно заданное имя имеет высший приоритет 

	$TRUSTLINK_USER //= $ENV{TRUSTLINK_USER} || ''; # у имени заданного через переменные окружения самый низкий приоритет
	
	$self->push_error('TRUSTLINK_USER is not set.') unless $TRUSTLINK_USER;	# без имени трастнинк нам ничего хорошего не скажет
	
	$self->{tl_host} =~ s/^www\.//;   # WTF? 
	
	unless ( $self->{tl_request_uri} ) {  # если 'request_uri' не был задан в параметрах, то формируем его сами
		$self->{tl_request_uri} = $ENV{REQUEST_URI} || '/';
		if ( $self->{tl_is_static} ) {
			s{\?.*$}{}, s{//*}{/}g for $self->{tl_request_uri};  # удаляем QUERY_STRING и дублирующиеся слеши
		}
	}
	
	$self->{tl_request_uri} = uri_unescape( $self->{tl_request_uri} );
	
	if ( $ENV{HTTP_TRUSTLINK} and $ENV{HTTP_TRUSTLINK} eq $TRUSTLINK_USER )	{ # если задана такая переменная окружения, включаем режим тестирования, робота и многословный
		$self->{"tl_$_"} = 1 for qw( test is_robot verbose );
	}
	
	return $self;
}

sub load_links {
	my $self = shift;
	my $ua = LWP::UserAgent::WithCache->new({ namespace           => 'tl-cache',
						  default_expires_in  => $self->{tl_cache_reloadtime},
						  auto_purge_interval => $self->{tl_cache_lifetime},
						  cache_root          => $self->{tl_cache_path},
					        });
	
	my $content = eval { $ua->get( join '/', $self->{tl_server},  $TRUSTLINK_USER, lc( $self->{tl_host} ), uc( $self->{tl_charset} ) . '.text' )->content };

	return $self->push_error("Error: $@")     if $@;
	return $self->push_error('Empty content') unless $content;
	return $self->push_error( $self->{tl_debug} ? $content : 'Fatal error' ) if $content =~ /^FATAL ERROR:/; # WTF?
	
	$self->{tl_file_size} = length $content;

	$self->_parse_links( $content ); # разбираем контент и складываем в $self->{tl_links}

	# если трастлинк отдал особые данные, то переключаем режимы (не уверен, что это хорошо, позволять трастлинку управлять нашим приложением)
	$self->{tl_verbose} = $self->{tl_force_show_code} = 1                    if $self->{tl_links}{__trustlink_debug__};
        $self->{tl_links_delimiter} = $self->{tl_links}{__trustlink_delimiter__} if $self->{tl_links}{__trustlink_delimiter__};

	if ( $self->{tl_test} ) { # в режиме тестирования заполняем страничку размноженной тестовой ссылкой
		push @{ $self->{tl_links_page} }, ( $self->{tl_links}{__test_tl_link__} ) x $self->{tl_test_count}
			if 'HASH' eq ref $self->{tl_links}{__test_tl_link__};
	}
	else { # а в боевом режиме в страничку заносим ссылки относящиеся к нашему request_uri
		$self->{tl_links_page} = $self->{tl_links}{ $self->{tl_request_uri} } if $self->{tl_links}{ $self->{tl_request_uri} };
	}
	$self->{tl_links_count} = @{ $self->{tl_links_page} };
	$self->{_links_loaded} = 1;
}


sub _parse_links {  # разбор контента, пришедшего от трастлинка
	my $self        = shift;
	my $content     = shift;

	$self->{tl_links} = {}; # сюда будем складывать
	
	my ( $test_tl_link ) = $content =~ m/^__test_tl_link__:(.*?)(?:\n\n|\z)/ims; # ищем тестовую сылку 
	$test_tl_link = { $test_tl_link =~ m{^(.*?):(.*?)$}msg }; # и делаем из неё хэш
	$content =~ s{^__test_tl_link__:(.*?)(?:\n\n|\z)}{}imsg;  # чистим контент от тестовых ссылок, чтоб они нам не попадались при поиске служебных слов

	my $match = { $content =~ m/^__([a-z_]+)__:(.*?)\n/imsg };   # ищем служебные теги, заносим их в хэш
	$match->{trustlink_robots} = [ split / <break> /, $match->{trustlink_robots} ]; # преобразовываем строку с ip-шниками роботов в массив 
	$match->{test_tl_link} = $test_tl_link; 

	$self->{tl_links}{ uri_unescape( "__${_}__" ) } = $match->{$_} for keys %$match; # сохраняем все служебные данные и тестовую ссылку

	if ( my ($cur_links) = $content =~ m{^\Q$self->{tl_request_uri}\E/?:(.*?)(?:\n\n|\z)}imsg ) { # ищем ссылки соответствующие нашему request_uri
		my @cur = map { s/^\s+//, s/\s+$//; $_ } split / <break> /, $cur_links;   # разбиваем запись на части и чистим эти части от пробелов со всех сторон
		push @{ $self->{tl_links}{ uri_unescape( $self->{tl_request_uri} ) } }, { $_ =~ m/^(.*?):(.*?)$/msg } for @cur; # делаем из тех частей хэши и сохраняем их
	}
}

sub push_error {  # занесение строки с ошибкой в специально предназначенный контейнер 
	push @{ shift->{errors} }, @_;
}

sub build_links { # вставляем ссылочки в шаблон и отдаём результат
	my $self = shift;
	
	$self->load_links unless $self->{_links_loaded}; # если ссылки ещё не загружены с трастлинка, грузим

	my $result = ''; # здесь будет результат

	# если от трастлика пришел спецкод и (у нас включен особый режим или нас запросил трастлинковский робот), то вставляем этот спецкод
	$result .= $self->{tl_links}{__trustlink_start__}
		if $self->{tl_links}{__trustlink_start__}
			and ( $self->{tl_force_show_code} or $self->{remote_addr} ~~ @{ $self->{tl_links}{__trustlink_robots__} } );

	# если многословный режим или нас запросил трастлинковский робот, то ... 
	$result .= <<EOT if $self->{tl_verbose} or  $self->{remote_addr} ~~ @{ $self->{tl_links}{__trustlink_robots__} };
<!-- REQUEST_URI=@{[ $ENV{REQUEST_URI} || '' ]} -->

<!--
L $VERSION
REMOTE_ADDR=$self->{remote_addr}
request_uri=$self->{tl_request_uri}
charset=$self->{tl_charset}
is_static=$self->{tl_is_static}
multi_site=$self->{tl_multi_site}
file_size=$self->{tl_file_size}
lc_links_count=$self->{tl_links_count}
left_links_count=$self->{tl_links_count}
-->
EOT
	my $tpl_filename = $self->{tl_tpath} . '/' . $self->{tl_template} . ".tpl.html"; # имя файла с шаблоном
	my $tpl = do { local( @ARGV, $/ ) = $tpl_filename; <> }; # заглатыавем содержимое файла в переменную
	$self->push_error("Template file no found") unless $tpl; # жалуемся, если шаблон пустой

	if ( my ( $block ) = $tpl =~ m/(<{block}>(.+)<{\/block}>)/is ) { # шаблон должен содержать такой блок, который будем заменять нашими ссылками

		my $blockT = substr($block, 9, -10); # здесь тело блока без обрамляющих тегов

		for ( qw( head_block /head_block link text host ) ) { # проверяем наличие шаблона на присутсвие необходимых тегов
			$self->push_error("Wrong template format: no <{$_}> tag.") unless $blockT =~ /<{$_}>/;
		}

		my $text = ''; # сюда будем добавлять готовые прошаблонизированные ссылочки 
		
		foreach my $link ( @{ $self->{tl_links_page} } ) {  # это ссылки для нашей страницы 
			$self->push_error("link is not a hashref: $link"), next unless 'HASH' eq ref $link; 
			$self->push_error("format of link must be a hash('anchor'=>\$anchor,'url'=>\$url,'text'=>\$text)"), next if !$link->{url} or !$link->{text};

			my $host = URI->new( $link->{url} )->host;
			$self->push_error("wrong format of url: ".$link->{url}), next unless $host;
			$self->push_error("wrong host: $host in url $link->{url}"), next unless $host =~ /\./;
			
			$host =~ s/^www\.//; # WTF?
			
			my $a = $blockT;
			$a =~ s/<{text}>/$link->{text}/gi;
			$a =~ s/<{host}>/$host/gi;

			if ( $link->{anchor} ) {
				my $href = $link->{punicode_url} || $link->{url};
				$a =~ s/<{link}>/<a href='$href'>$link->{anchor}<\/a>/gi;
				$a =~ s/<{head_block}>//i;
				$a =~ s/<{\/head_block}>//i;
			}
			else {
				$a =~ s/<{head_block}>(.+)<{\/head_block}>//is;				
			}
			
			$text .= $a;
		}
		$tpl =~ s/\Q$block/$text/;  # заменяем блок сформированным текстом
		$result .= $tpl;	    # и добавляем его в результат	
	}
	else {
		$self->push_error('Wrong template format: no <{block}><{/block}> tags'); # жалуемся
	}
	
	# если от трастлика пришел спецкод и (у нас включен особый режим или нас запросил трастлинковский робот), то вставляем этот спецкод	
	$result .= $self->{tl_links}{__trustlink_end__}
		if $self->{tl_links}{__trustlink_end__} and ( $self->{tl_force_show_code} or $self->{remote_addr} ~~ @{$self->{tl_links}{__trustlink_robots__}} );

	# для тестового режима, если это не режим робота обрамляем в noindex
	$result = '<noindex>' . $result . '</noindex>' if $self->{tl_test} and !$self->{tl_is_robot};

	# в режиме дебага вываливаем накопившиеся ошибки
	$result .= join "\n", '<!-- ERRORS:', @{ $self->{errors} }, '-->'
		if $self->{tl_debug} and @{ $self->{errors} };

	return $result;
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

