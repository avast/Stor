requires 'perl', '5.022';
requires 'Mojolicious';
requires 'Path::Tiny';
requires 'Syntax::Keyword::Try';
requires 'List::MoreUtils';
requires 'Digest::SHA';
requires 'Cpanel::JSON::XS';

on 'test' => sub {
    requires 'Test::More', '0.98';
};

on 'develop' => sub {
    requires 'Minilla';
    requires 'Module::Build::Tiny';
};
