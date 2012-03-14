package Moonpig::Role::Env::ExceptionReportEmail;
# ABSTRACT: an environment that sends exception reports via email

use Moose::Role;
with qw(Moonpig::Role::Env Moonpig::Role::Env::EmailSender);

use Moonpig::Types qw(Ledger);
use Stick::Util qw(ppack);

use namespace::autoclean;

requires 'exception_report_from_email_address';
requires 'exception_report_to_email_address';
requires 'exception_report_mkit_name';

sub report_exception {
  my ($self, $exception, $dumpable, $arg) = @_;
  $dumpable //= {};
  $arg      //= {};

  my $email = Moonpig->env->mkits->assemble_kit(
    $self->exception_report_mkit_name,
    {
      to_addresses => [ $self->customer_service_to_email_address->as_string ],
      subject   => 'Exception Report',
      exception => $exception,
      dumpable  => $dumpable,
    },
  );

  my $env = {
    to   => [ $self->exception_report_to_email_address->address ],
    from => $self->exception_report_from_email_address->address,
  };

  $self->send_email($email, $env);
}

1;
