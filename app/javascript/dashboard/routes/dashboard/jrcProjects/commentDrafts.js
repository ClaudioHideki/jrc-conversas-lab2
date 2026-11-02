const databaseName = 'jrc-project-comment-drafts';
const queues = new Map();

export function commentDraftKey(scope) {
  const values = ['accountId', 'userId', 'projectId', 'taskId'].map(key =>
    String(scope[key] || '')
  );
  if (values.some(value => !/^\d+$/.test(value)))
    throw new Error('Contexto de rascunho inválido.');
  const comment = scope.commentId == null ? 'new' : String(scope.commentId);
  if (comment !== 'new' && !/^\d+$/.test(comment))
    throw new Error('Comentário de rascunho inválido.');
  return [...values, comment].join(':');
}

function transact(action, key, value) {
  return new Promise((resolve, reject) => {
    if (!window.indexedDB) {
      reject(new Error('Rascunho local indisponível neste navegador.'));
      return;
    }
    const open = window.indexedDB.open(databaseName, 1);
    open.onupgradeneeded = () => open.result.createObjectStore('drafts');
    open.onerror = () => reject(open.error);
    open.onsuccess = () => {
      const db = open.result;
      const transaction = db.transaction(
        'drafts',
        action === 'get' ? 'readonly' : 'readwrite'
      );
      const store = transaction.objectStore('drafts');
      let operation;
      if (action === 'get') operation = store.get(key);
      else if (action === 'delete') operation = store.delete(key);
      else operation = store.put(value, key);
      let result;
      operation.onsuccess = () => {
        result = operation.result;
      };
      transaction.oncomplete = () => {
        db.close();
        resolve(result);
      };
      transaction.onabort = () => {
        db.close();
        reject(transaction.error);
      };
      transaction.onerror = () => {
        db.close();
        reject(transaction.error);
      };
    };
  });
}

export function commentDraft(action, scope, value) {
  const key = commentDraftKey(scope);
  const previous = queues.get(key) || Promise.resolve();
  const task = previous
    .catch(() => undefined)
    .then(() => transact(action, key, value));
  queues.set(key, task);
  const clean = () => {
    if (queues.get(key) === task) queues.delete(key);
  };
  task.then(clean, clean);
  return task;
}
