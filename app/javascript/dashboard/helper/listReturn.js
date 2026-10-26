export function canReturnToAccountList(
  router,
  accountId,
  names,
  back = window.history.state?.back
) {
  if (
    typeof back !== 'string' ||
    !back.startsWith('/') ||
    back.startsWith('//')
  )
    return false;
  const destination = router.resolve(back);
  return (
    String(destination.params.accountId) === String(accountId) &&
    names.includes(destination.name)
  );
}
