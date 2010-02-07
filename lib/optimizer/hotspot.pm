package optimizer::hotspot;

use 5.008_001;
use strict;
use warnings;

our $VERSION = '0.001';

use XSLoader;
XSLoader::load(__PACKAGE__, $VERSION);

1;
__END__

=head1 NAME

optimizer::hotspot - Perl extention to do something

=head1 VERSION

This document describes optimizer::hotspot version 0.001.

=head1 SYNOPSIS

    use optimizer::hotspot; # does optimization as much as possible

    use optimizer::hotspot 0xFFFF00; # default

    use optimizer::hotspot 0xFFFF01; # trace optimization

=head1 DESCRIPTION

optimizer::hotspot provides blah blah blah.

=head1 INTERFACE

=head2 Class methods

=over 4

=item *

=back

=head2 Instance methods

=over 4

=item *

=back


=head1 DEPENDENCIES

Perl 5.8.1 or later, and a C compiler.

=head1 BUGS

No bugs have been reported.

Please report any bugs or feature requests to the author.

=head1 SEE ALSO

L<perl>

=head1 AUTHOR

Goro Fuji (gfx) E<lt>gfuji(at)cpan.orgE<gt>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2010, Goro Fuji (gfx). All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. See L<perlartistic> for details.

=cut
