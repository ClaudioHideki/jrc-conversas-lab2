export const sanitizeSipMessage = (message, secrets = []) => {
  let text = String(message || '');
  secrets.filter(Boolean).forEach(secret => {
    text = text.split(String(secret)).join('[REDACTED]');
  });
  // Discard the remainder of a line carrying authentication material.
  return text
    .replace(
      /(?:authorization|proxy-authorization|cookie|set-cookie|password|token|secret)\s*[=:]\s*[^\r\n]*/gi,
      '[REDACTED]'
    )
    .slice(0, 512);
};

export const sipActionError = error => {
  const mediaErrors = {
    NotAllowedError:
      'Acesso ao microfone negado. Autorize o microfone no navegador ou nas configurações de privacidade do Windows.',
    PermissionDeniedError:
      'Acesso ao microfone negado. Autorize o microfone para realizar chamadas.',
    NotFoundError:
      'Nenhum microfone foi encontrado. Conecte um dispositivo de áudio.',
    DevicesNotFoundError:
      'Nenhum microfone foi encontrado. Conecte um dispositivo de áudio.',
    NotReadableError:
      'O microfone está indisponível. Verifique se outro aplicativo está usando o dispositivo.',
    TrackStartError:
      'O microfone está indisponível. Verifique o dispositivo de áudio.',
    AbortError:
      'Não foi possível iniciar o microfone. Verifique o dispositivo e tente novamente.',
  };
  return (
    mediaErrors[error?.name] ||
    error?.message ||
    'Não foi possível concluir a ação.'
  );
};
