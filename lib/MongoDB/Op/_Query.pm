#
#  Copyright 2014 MongoDB, Inc.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#

package MongoDB::Op::_Query;

# Encapsulate a query operation; returns a MongoDB::QueryResult object

use version;
our $VERSION = 'v0.999.999.4'; # TRIAL

use Moo;

use MongoDB::BSON;
use MongoDB::QueryResult;
use MongoDB::_Constants;
use MongoDB::_Protocol;
use MongoDB::_Types -types;
use Types::Standard -types;
use namespace::clean;

has db_name => (
    is       => 'ro',
    required => 1,
    ( WITH_ASSERTS ? ( isa => Str ) : () ),
);

has coll_name => (
    is       => 'ro',
    required => 1,
    ( WITH_ASSERTS ? ( isa => Str ) : () ),
);

has client => (
    is       => 'ro',
    required => 1,
    ( WITH_ASSERTS ? ( isa => InstanceOf['MongoDB::MongoClient'] ) : () ),
);

has query => (
    is       => 'ro',
    required => 1,
    writer   => '_set_query',
    ( WITH_ASSERTS ? ( isa => Document ) : () ),
);

has projection => (
    is     => 'ro',
    ( WITH_ASSERTS ? ( isa => Document ) : () ),
);

has [qw/batch_size limit skip/] => (
    is      => 'ro',
    default => 0,
    ( WITH_ASSERTS ? ( isa => Num ) : () ),
);

# XXX eventually make this a hash with restricted keys?
has query_flags => (
    is      => 'ro',
    default => sub { {} },
    ( WITH_ASSERTS ? ( isa => HashRef ) : () ),
);

has post_filter => (
    is        => 'ro',
    predicate => 'has_post_filter',
    ( WITH_ASSERTS ? ( isa => Maybe[CodeRef] ) : () ),
);

with 'MongoDB::Role::_ReadOp';
with 'MongoDB::Role::_ReadPrefModifier';

sub execute {
    my ( $self, $link, $topology_type ) = @_;

    my $ns         = $self->db_name . "." . $self->coll_name;
    my $filter     = $self->bson_codec->encode_one( $self->query );
    my $batch_size = $self->limit || $self->batch_size;            # limit trumps

    my $proj =
      $self->projection ? $self->bson_codec->encode_one( $self->projection ) : undef;

    $self->_apply_read_prefs( $link, $topology_type );

    my ( $op_bson, $request_id ) =
      MongoDB::_Protocol::write_query( $ns, $filter, $proj, $self->skip, $batch_size,
        $self->query_flags );

    my $result =
      $self->_query_and_receive( $link, $op_bson, $request_id, $self->bson_codec );

    my $class =
      $self->has_post_filter ? "MongoDB::QueryResult::Filtered" : "MongoDB::QueryResult";

    return $class->new(
        _client     => $self->client,
        bson_codec  => $self->bson_codec,
        address     => $link->address,
        ns          => $ns,
        limit       => $self->limit,
        batch_size  => $batch_size,
        reply       => $result,
        post_filter => $self->post_filter,
    );
}

1;
