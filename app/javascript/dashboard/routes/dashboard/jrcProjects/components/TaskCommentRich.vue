<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import {
  buildEditor,
  EditorState,
  EditorView,
  Selection,
  fullSchema,
} from '@chatwoot/prosemirror-schema';
import { useProjects } from '../useProjects';
import {
  commentDocument,
  commentImageKeys,
  imageKey,
  serializeComment,
} from '../commentDocument';
import { commentDraft, commentDraftKey } from '../commentDrafts';
import { errorMessage, operationKey, request } from '../../jrcOperations/api';
import OpsModal from '../../jrcOperations/components/OpsModal.vue';

const props = defineProps({
  scope: { type: Object, required: true },
  comment: { type: Object, default: null },
  readonly: Boolean,
  disabled: Boolean,
});
const emit = defineEmits(['submit', 'change', 'cancel', 'draftState']);
const { projectText } = useProjects();
const mountPoint = ref(null);
const picker = ref(null);
const loading = ref(true);
const error = ref('');
const draftError = ref('');
const preview = ref('');
const content = ref('');
let view;
let generation = 0;
let timer;
let requestKey = operationKey();
let staged = new Map();
let urls = new Map();
let pendingImages = new Map();
let controller = new AbortController();
let draftQueue = Promise.resolve();
let activeScope;
let acknowledged = false;
let draftAvailable = true;
const scopeKey = computed(() => commentDraftKey(props.scope));
const valid = computed(
  () => !loading.value && !props.disabled && content.value.trim().length > 0
);

function saveDraft() {
  if (props.readonly || !view || acknowledged || !draftAvailable) return;
  const scope = { ...activeScope };
  const turn = generation;
  const body = serializeComment(view.state.doc);
  const keys = commentImageKeys(view.state.doc);
  const data = {
    body,
    requestKey,
    images: [...staged].filter(([key]) => keys.includes(key)),
  };
  draftQueue = (
    body.trim()
      ? commentDraft('put', scope, data)
      : commentDraft('delete', scope)
  ).catch(err => {
    if (turn === generation) {
      draftAvailable = false;
      emit('draftState', false);
      draftError.value = errorMessage(err);
    }
  });
}
function changed() {
  content.value = serializeComment(view.state.doc);
  emit('change', content.value);
  clearTimeout(timer);
  timer = setTimeout(saveDraft, 300);
}
function release() {
  generation += 1;
  controller.abort();
  controller = new AbortController();
  view?.destroy();
  view = null;
  urls.forEach(url => URL.revokeObjectURL(url));
  urls = new Map();
  pendingImages = new Map();
  staged = new Map();
  preview.value = '';
}
async function loadImageUrl(key, turn) {
  if (urls.has(key)) return urls.get(key);
  const file = staged.get(key);
  let blob = file;
  if (!blob) {
    const image = props.comment?.inline_images?.find(row => row.key === key);
    if (!image || !/^\d+$/.test(String(image.id))) return null;
    const { accountId, projectId, taskId } = props.scope;
    blob = await request(
      accountId,
      `projects/projects/${projectId}/tasks/${taskId}/comments/${props.comment.id}/images/${image.id}`,
      { responseType: 'blob', signal: controller.signal }
    );
  }
  if (turn !== generation) return null;
  const url = URL.createObjectURL(blob);
  urls.set(key, url);
  return url;
}
function imageUrl(key, turn) {
  if (!pendingImages.has(key)) pendingImages.set(key, loadImageUrl(key, turn));
  return pendingImages.get(key);
}
function imageView(node) {
  const image = document.createElement('img');
  image.className = 'max-w-full max-h-96 rounded-lg cursor-zoom-in';
  image.alt = node.attrs.alt || projectText('IMAGES', 'Imagens');
  const turn = generation;
  const key = imageKey(node.attrs.src);
  if (key)
    imageUrl(key, turn)
      .then(url => {
        if (url && turn === generation) image.src = url;
      })
      .catch(err => {
        if (turn === generation && !controller.signal.aborted)
          error.value = errorMessage(err);
      });
  const enlarge = () => {
    if (image.src) preview.value = image.src;
  };
  image.onclick = () => {
    if (props.readonly) enlarge();
  };
  image.ondblclick = enlarge;
  return { dom: image };
}
function insertImages(files, position = null) {
  if (!view || props.disabled || props.readonly) return;
  error.value = '';
  const images = Array.from(files).filter(file =>
    file.type.startsWith('image/')
  );
  if (!images.length) return;
  if (
    commentImageKeys(view.state.doc).length + images.length > 10 ||
    images.some(
      file =>
        !['image/png', 'image/jpeg', 'image/gif', 'image/webp'].includes(
          file.type
        ) ||
        !file.size ||
        file.size > 10 * 1024 * 1024
    )
  ) {
    error.value =
      'Use até 10 imagens PNG, JPEG, GIF ou WebP de até 10 MB por comentário.';
    return;
  }
  if (position != null)
    view.dispatch(
      view.state.tr.setSelection(
        Selection.near(view.state.doc.resolve(position))
      )
    );
  images.forEach(file => {
    const key = operationKey();
    staged.set(key, file);
    const node = fullSchema.nodes.image.create({
      src: `comment-image:${key}`,
      alt: file.name,
    });
    view.dispatch(view.state.tr.replaceSelectionWith(node).scrollIntoView());
  });
  // A trailing paragraph keeps typing available after the last print.
  const last = view.state.doc.lastChild;
  if (last?.lastChild?.type.name === 'image') {
    const transaction = view.state.tr.insert(
      view.state.doc.content.size,
      fullSchema.nodes.paragraph.create()
    );
    view.dispatch(transaction.setSelection(Selection.atEnd(transaction.doc)));
  }
  view.focus();
}
async function initialize(restoreDraft = true) {
  clearTimeout(timer);
  release();
  const turn = generation;
  loading.value = true;
  error.value = '';
  if (restoreDraft || draftAvailable) draftError.value = '';
  activeScope = { ...props.scope };
  acknowledged = false;
  let body = props.comment?.body || '';
  requestKey = operationKey();
  if (!props.readonly && restoreDraft) {
    try {
      const saved = await commentDraft('get', props.scope);
      if (turn !== generation) return;
      draftAvailable = true;
      emit('draftState', true);
      if (saved) {
        body = saved.body;
        requestKey = saved.requestKey;
        staged = new Map(saved.images);
      }
    } catch (err) {
      draftAvailable = false;
      emit('draftState', false);
      draftError.value = errorMessage(err);
    }
  }
  if (turn !== generation || !mountPoint.value) return;
  const plugins = props.readonly
    ? []
    : buildEditor({
        schema: fullSchema,
        placeholder: projectText('INTERNAL_COMMENT', 'Comentário interno'),
        methods: { onImageUpload: () => picker.value?.click() },
        enabledMenuOptions: [
          'strong',
          'em',
          'link',
          'bulletList',
          'orderedList',
          'imageUpload',
          'undo',
          'redo',
        ],
      });
  view = new EditorView(mountPoint.value, {
    state: EditorState.create({ doc: commentDocument(body), plugins }),
    editable: () => !props.readonly && !props.disabled,
    nodeViews: { image: imageView },
    attributes: {
      'aria-label': projectText('INTERNAL_COMMENT', 'Comentário interno'),
      class: 'min-h-28 p-3 outline-none break-words',
    },
    dispatchTransaction(transaction) {
      view.updateState(view.state.applyTransaction(transaction).state);
      if (transaction.docChanged) changed();
    },
    handlePaste(_view, event) {
      if (!event.clipboardData?.files.length) return false;
      event.preventDefault();
      insertImages(event.clipboardData.files);
      return true;
    },
    handleDrop(_view, event, _slice, moved) {
      if (moved || !event.dataTransfer?.files.length) return false;
      event.preventDefault();
      insertImages(
        event.dataTransfer.files,
        view.posAtCoords({ left: event.clientX, top: event.clientY })?.pos
      );
      return true;
    },
  });
  content.value = serializeComment(view.state.doc);
  loading.value = false;
  emit('change', props.readonly ? '' : content.value);
}
async function reset() {
  clearTimeout(timer);
  acknowledged = true;
  await draftQueue;
  await commentDraft('delete', activeScope).catch(err => {
    draftAvailable = false;
    emit('draftState', false);
    draftError.value = errorMessage(err);
  });
  release();
  content.value = '';
  emit('change', '');
  if (!props.comment) await initialize(false);
}
function submit() {
  if (!valid.value || !view) return;
  const keys = commentImageKeys(view.state.doc);
  emit('submit', {
    body: serializeComment(view.state.doc),
    requestKey,
    images: [...staged]
      .filter(([key]) => keys.includes(key))
      .map(([key, file]) => ({ key, file })),
    onSaved: reset,
  });
}
async function discard() {
  clearTimeout(timer);
  acknowledged = true;
  await draftQueue;
  try {
    if (draftAvailable) await commentDraft('delete', activeScope);
  } catch (err) {
    acknowledged = false;
    throw err;
  }
  release();
  content.value = '';
  emit('change', '');
}
async function cancel() {
  try {
    await discard();
    emit('cancel');
  } catch (err) {
    error.value = errorMessage(err);
  }
}
defineExpose({ reset, discard, insertImages });
watch(
  () => props.disabled,
  () => view?.setProps({ editable: () => !props.readonly && !props.disabled })
);
watch([scopeKey, () => (props.readonly ? props.comment?.body : null)], () => {
  saveDraft();
  initialize();
});
onMounted(initialize);
onBeforeUnmount(() => {
  clearTimeout(timer);
  saveDraft();
  release();
});
</script>

<template>
  <div class="grid gap-2" data-testid="rich-task-comment">
    <p v-if="loading" role="status">
      {{ projectText('TASK_LOADING', 'Carregando tarefa...') }}
    </p>
    <div
      ref="mountPoint"
      class="rounded-lg border border-n-weak bg-n-solid-1 [&_a]:text-n-blue-11 [&_ul]:list-disc [&_ol]:list-decimal [&_li]:ml-5"
    />
    <template v-if="!readonly">
      <input
        ref="picker"
        type="file"
        accept="image/png,image/jpeg,image/gif,image/webp"
        multiple
        class="hidden"
        :disabled="disabled"
        @change="
          insertImages($event.target.files);
          $event.target.value = '';
        "
      />
      <div class="flex flex-wrap justify-between gap-2">
        <button
          v-if="comment"
          type="button"
          :disabled="disabled || loading"
          class="rounded border border-n-weak px-3 py-2"
          @click="cancel"
        >
          {{ projectText('CANCEL', 'Cancelar') }}
        </button>
        <button
          type="button"
          :disabled="disabled || loading"
          class="rounded border border-n-weak px-3 py-2"
          @click="picker?.click()"
        >
          {{ projectText('UPLOAD_FILES', 'Enviar arquivos') }}
        </button>
        <button
          type="button"
          :disabled="!valid"
          class="rounded bg-n-blue-9 px-3 py-2 text-white disabled:opacity-50"
          @click="submit"
        >
          {{ projectText('ADD_COMMENT', 'Registrar comentário') }}
        </button>
      </div>
      <p v-if="draftError" role="status" class="text-sm text-n-amber-11">
        {{ draftError }}
      </p>
    </template>
    <p v-if="error" role="alert" class="text-sm text-n-ruby-11">{{ error }}</p>
    <OpsModal
      v-if="preview"
      :title="projectText('IMAGES', 'Imagens')"
      wide
      @close="preview = ''"
    >
      <img
        :src="preview"
        :alt="projectText('IMAGES', 'Imagens')"
        class="max-h-[80vh] max-w-full rounded"
      />
    </OpsModal>
  </div>
</template>
