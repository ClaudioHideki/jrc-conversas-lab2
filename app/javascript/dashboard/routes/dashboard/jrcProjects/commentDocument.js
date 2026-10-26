import {
  ArticleMarkdownSerializer,
  ArticleMarkdownTransformer,
  fullSchema,
} from '@chatwoot/prosemirror-schema';

export const imageKey = source =>
  /^comment-image:([a-zA-Z0-9-]{16,80})$/.exec(source || '')?.[1];

export const commentDocument = body => {
  const json = new ArticleMarkdownTransformer(fullSchema)
    .parse(body || '')
    .toJSON();
  const sanitize = node => {
    if (node.type === 'image' && !imageKey(node.attrs?.src)) return null;
    if (node.marks) {
      node.marks = node.marks.filter(
        mark =>
          mark.type !== 'link' ||
          /^(https?:\/\/|mailto:)/i.test(mark.attrs?.href || '')
      );
    }
    if (node.content) node.content = node.content.map(sanitize).filter(Boolean);
    return node;
  };
  return fullSchema.nodeFromJSON(sanitize(json));
};
export const serializeComment = doc => ArticleMarkdownSerializer.serialize(doc);
export const commentImageKeys = doc => {
  const keys = [];
  doc.descendants(node => {
    if (node.type.name === 'image' && imageKey(node.attrs.src))
      keys.push(imageKey(node.attrs.src));
  });
  return [...new Set(keys)];
};

export function commentFormData(payload) {
  const form = new FormData();
  form.append('comment[body]', payload.body);
  form.append('comment[content_format]', 'markdown');
  payload.images.forEach(({ key, file }) =>
    form.append(`comment[images][${key}]`, file, file.name)
  );
  return form;
}
