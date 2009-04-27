# $Id: Tag.pm 112 2006-01-09 16:52:08Z chronos $
package BBCode::Tag;
use BBCode::Util qw(:quote :tag);
use BBCode::TagSet;
use Carp qw(croak);
use HTML::Entities ();
use strict;
use warnings;
our $VERSION = '0.21';

=head1 NAME

BBCode::Tag - Perl representation of a BBCode tag

=head1 DESCRIPTION

See the documentation on L<BBCode::Parser> for an overview of the typical
usage of this package.

=head1 METHODS

=cut

# Class methods meant for overriding

=head2 Tag

C<Tag> returns the name of the tag as used in BBCode.

The default implementation returns the final component of the object's class
name; override this in subclasses as needed.

=cut

sub Tag($):method {
	my $class = shift;
	$class = ref($class) || $class;
	$class =~ s/'/::/g;
	$class =~ s/^.*:://;
	return $class;
}

=head2 Class

C<Class> returns a list of zero or more strings, each of which is a class
that this tag belongs to (without any colons).  For instance, [B] and [I] tags
are both of class :INLINE, meaning that they can be found inside fellow inline
tags.  Tag classes are listed in order from most specific to least.

The default implementation returns an empty list.

=cut

sub Class($):method {
	return ();
}

=head2 BodyPermitted

C<BodyPermitted> indicates whether or not the tag can contain a body of some
sort (whether it be text, more tags, or both).

The default implementation returns false.

=cut

sub BodyPermitted($):method {
	return 0;
}

=head2 BodyTags

C<BodyTags> returns a list of tags and classes that are permitted or forbidden
in the body of this tag.  See L<BBCode::Parser-E<gt>permit()|BBCode::Parser/"permit">
for syntax.  If this tag doesn't permit a body at all, this value is ignored.

The default implementation returns an empty list.

=cut

sub BodyTags($):method {
	return ();
}

sub NamedParams($):method {
	return ();
}

sub RequiredParams($):method {
	return shift->NamedParams;
}

sub DefaultParam($):method {
	return undef;
}

sub OpenPre($):method {
	return "";
}

sub OpenPost($):method {
	return "";
}

sub ClosePre($):method {
	return "";
}

sub ClosePost($):method {
	return "";
}

# Instance methods meant for overriding

sub validateParam($$$):method {
	return $_[2];
}

# Methods meant to be inherited

sub _create($$@):method {
	my $class = shift;
	my $parser = shift;
	my $this = bless {
		parser	=> $parser,
		params	=> {},
	}, $class;

	if($this->BodyPermitted) {
		$this->{body} = [];
		$this->{permit} = BBCode::TagSet->new;
		$this->{forbid} = BBCode::TagSet->new;
		if($this->BodyTags) {
			$this->{permit}->add($this->BodyTags);
		} else {
			$this->{permit}->add(':ALL');
		}
	}

	foreach($this->NamedParams) {
		$this->{params}->{$_} = undef;
	}

	while(@_) {
		my($k,$v) = (undef,shift);
		($k,$v) = @$v if ref $v and UNIVERSAL::isa($v,'ARRAY');
		$k = $this->DefaultParam if not defined $k or $k eq '';
		croak "No default parameter for [".$this->Tag."]" if not defined $k;
		$this->param($k, $v);
	}

	return $this;
}

=head2 new

	$parser = BBCode::Parser->new(...);
	$tag = BBCode::Tag->new($parser, 'B');

Constructs a new tag of the appropriate subclass.

=cut

sub new($$$@):method {
	shift;
	my $parser = shift;
	my $tag = shift;
	my $pkg = tagLoadPackage($tag);
	$tag = $pkg->Tag;

	croak "Tag [$tag] is not permitted by current settings"
		if not $parser->isPermitted($tag);

	return $pkg->_create($parser, @_);
}

=head2 parser

	$parser = $tag->parser();

Returns the C<BBCode::Parser> that this tag was constructed with.

=cut

sub parser($):method {
	return shift->{parser};
}

=head2 isPermitted

	if($tag->isPermitted('URL')) {
		# $tag can contain [URL] tags
	} else {
		# [URL] tags are forbidden
	}

=cut

sub isPermitted($$):method {
	my($this,$child) = @_;
	if(exists $this->{body}) {
		foreach(tagHierarchy($child)) {
			return 0 if $this->{forbid}->contains($_);
			return 1 if $this->{permit}->contains($_);
		}
	}
	return 0;
}

=head2 forbidTags

	$tag->forbidTags(qw(IMG URL));

Mark the given tag(s) as forbidden, so that this tag (nor any of its children,
grandchildren, etc.) can contain any forbidden tag.

At the moment, if a tag already contains one of the tags now forbidden, a
warning is raised.  In the future, this behavior will likely change.

=cut

sub forbidTags($@):method {
	my $this = shift;
	if(exists $this->{body}) {
		my $set;
		if(@_ == 1 and UNIVERSAL::isa($_[0],'BBCode::TagSet')) {
			$set = shift;
		} else {
			$set = BBCode::TagSet->new(@_);
		}
		$this->{permit}->remove($set);
		$this->{forbid}->add($set);
		foreach my $child ($this->body) {
			warn qq(Nested child is now forbidden) unless $this->isPermitted($child);
			$child->forbidTags($set);
		}
	}
	return $this;
}

=head2 body

	# Iterate over all this tag's immediate children
	my @body = $tag->body();
	foreach my $subtag (@body) { ...; }

	# Forcibly add a new child, overriding $tag->isPermitted()
	my $body = $tag->body();
	my $bold = BBCode::Tag->new($tag->parser(), 'B');
	push @$body, $bold;

Returns the list of child tags for this tag.  In list context, returns
a list; otherwise, returns an array reference.

CAUTION: The returned reference is a direct pointer to a C<BBCode::Tag>
internal structure.  It is possible to bypass checks on security and
correctness by altering it directly.

=cut

sub body($):method {
	my $this = shift;
	if(exists $this->{body}) {
		return @{$this->{body}} if wantarray;
		return $this->{body};
	} else {
		return () if wantarray;
		return [];
	}
}

=head2 bodyHTML

	print HANDLE $tag->bodyHTML();

Recursively converts this tag and everything inside it into HTML text.  In
array context, returns the HTML line-by-line (with CRLF already appended);
in scalar context, returns the HTML as one string.

=cut

sub bodyHTML($):method {
	my @html = grep { defined } map { $_->toHTML } shift->body;
	return @html if wantarray;
	return join "", @html;
}

=head2 pushBody
	$tag->pushBody(
		BBCode::Tag->new($tag->parser(), 'IMG', 'http://www.example.org/img.png')
	);

Appends one or more new child tags to this tag's body.  Security and
correctness checks are performed.

If any arguments are strings, they are upgraded to virtual [TEXT] tags.

=cut

sub pushBody($@):method {
	my $this = shift;
	croak qq(Body contents not permitted) unless $this->BodyPermitted;
	while(@_) {
		my $tag = shift;
		if(ref $tag) {
			croak qq(Expected a BBCode::Tag) unless UNIVERSAL::isa($tag, 'BBCode::Tag');
		} else {
			$tag = BBCode::Tag->new($this->{parser}, 'TEXT', [ undef, $tag ]);
		}
		croak qq(Invalid tag nesting) if not $this->isPermitted($tag);
		$tag->forbidTags($this->{forbid});
		push @{$this->{body}}, $tag;
	}
	return $this;
}

sub param($$;$):method {
	my($this,$param) = splice @_, 0, 2;

	$param = $this->DefaultParam if not defined $param;
	croak qq(Missing parameter name) unless defined $param;
	$param = uc $param;
	croak qq(Invalid parameter name "$param") unless exists $this->{params}->{$param};

	if(@_) {
		$this->{params}->{$param} = $this->validateParam($param,@_);
	}

	return $this->{params}->{$param};
}

sub params($):method {
	my $this = shift;
	my @ret;
	foreach my $k ($this->NamedParams) {
		next unless exists $this->{params}->{$k};
		my $v = $this->{params}->{$k};
		push @ret, $k, $v if defined $v;
	}
	return @ret if wantarray;
	return { @ret };
}

sub replace($):method {
	return $_[0];
}

sub replaceBody($):method {
	my $this = shift->replace;
	my $body = $this->body;
	@$body = grep { defined } map { $_->replaceBody } @$body;
	return $this;
}

sub isFollowed($):method {
	my $this = shift;
	my $follow = $this->parser->follow_links;
	if($this->parser->follow_override) {
		eval {
			my $f = $this->param('FOLLOW');
			$follow = $f if defined $f;
		};
	}
	return $follow;
}

sub toBBCode($):method {
	my $this = shift;

	my $ret = $this->OpenPre.'['.$this->Tag;

	my @p = $this->params;

	if(@p) {
		my $def = $this->DefaultParam;
		my @params;

		while(@p) {
			my($k,$v) = splice @p, 0, 2;
			if(defined $def and $def eq $k) {
				$ret .= '='.quote($v);
				$def = undef;
			} else {
				push @params, quote($k).'='.quote($v);
			}
		}

		$ret = join(", ", $ret, @params);
	}

	$ret .= ']'.$this->OpenPost;

	if($this->BodyPermitted) {
		foreach($this->body) {
			$ret .= $_->toBBCode;
		}
		$ret .= $this->ClosePre.'[/'.$this->Tag.']'.$this->ClosePost;
	}

	return $ret;
}

sub toHTML($):method {
	croak qq(Not implemented);
}

sub toLinkList($;$):method {
	my $this = shift;
	my $ret = @_ ? shift : [];
	foreach($this->body) {
		$_->toLinkList($ret);
	}
	return @$ret if wantarray;
	return $ret;
}

1;

=head1 SEE ALSO

L<BBCode::Parser>

=head1 AUTHOR

Donald King E<lt>dlking@cpan.orgE<gt>

=cut
