package Moonpig::Role::Env::ExceptionReportEmail;
# ABSTRACT: an environment that sends exception reports via email

use Moose::Role;
with qw(Moonpig::Role::Env Moonpig::Role::Env::EmailSender);

use Exception::Reporter;
use Exception::Reporter::Dumpable::File;
use Exception::Reporter::Summarizer::Email;
use Exception::Reporter::Summarizer::File;
use Exception::Reporter::Summarizer::ExceptionClass;
use Exception::Reporter::Summarizer::Fallback;
use Moonpig::Types qw(Ledger);
use Stick::Util qw(ppack);

use namespace::autoclean;

requires 'exception_report_from_email_address';
requires 'exception_report_to_email_address';
requires 'exception_report_mkit_name';

has _exception_reporter => (
  is  => 'ro',
  isa => 'Exception::Reporter',
  builder => '_build_exception_reporter',
);

package
  Moonpig::Exception::Reporter {
  use parent 'Exception::Reporter::Sender::Email';

  use Moonpig::Logger '$Logger';
  use Try::Tiny;

  sub send_email {
    my ($self, $email, $env) = @_;
    try   { Moonpig->env->send_email($email, $env); }
    catch { $Logger->log("error sending exception report: $_") };
  }
}

sub _build_exception_reporter {
  my ($self) = @_;
  return Exception::Reporter->new({
    # always_dump => { env => sub { \%ENV } },
    senders     => [
      Moonpig::Exception::Reporter->new({
        to   => [ $self->exception_report_to_email_address->address ],
        from => $self->exception_report_from_email_address->address,
      }),
    ],
    summarizers => [
      Exception::Reporter::Summarizer::Email->new,
      Exception::Reporter::Summarizer::File->new,
      Exception::Reporter::Summarizer::ExceptionClass->new,
      Exception::Reporter::Summarizer::Fallback->new,
    ],
  });
}

sub report_exception {
  my ($self, $dumpable, $arg) = @_;
  $arg //= {};

  $self->_exception_reporter->report_exception(
    $dumpable,
    {
      reporter => 'Moonpig',
      %$arg,
    },
  );
}

1;
