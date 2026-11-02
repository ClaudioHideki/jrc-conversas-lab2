import { describe, expect, it } from 'vitest';
import {
  commentDocument,
  commentFormData,
  commentImageKeys,
  serializeComment,
} from '../commentDocument';
import { commentDraftKey } from '../commentDrafts';

const key = 'synthetic-image-00000001';
describe('comment rich document contract', () => {
  it('round-trips text, multiple inline images and formatting in their original order', () => {
    const body = `**Before**\n\n![First](comment-image:${key})\n\n*Between*\n\n![Second](comment-image:synthetic-image-00000002)\n\nAfter\n\n- one\n- two`;
    const doc = commentDocument(body);
    const output = serializeComment(doc);
    expect(commentImageKeys(doc)).toEqual([key, 'synthetic-image-00000002']);
    expect(output.indexOf('Before')).toBeLessThan(output.indexOf(key));
    expect(output.indexOf(key)).toBeLessThan(output.indexOf('Between'));
    expect(output.indexOf('Between')).toBeLessThan(
      output.indexOf('synthetic-image-00000002')
    );
    expect(output.indexOf('synthetic-image-00000002')).toBeLessThan(
      output.indexOf('After')
    );
    expect(serializeComment(commentDocument(output))).toBe(output);
    expect(output).toContain('**Before**');
    expect(output).toContain('*Between*');
  });
  it.each([
    'https://outside.invalid/track.png',
    'data:image/png;base64,AAAA',
    'blob:https://outside.invalid/id',
  ])('does not render or serialize an unowned image: %s', source => {
    const doc = commentDocument(`Before ![outside](${source}) after`);
    expect(commentImageKeys(doc)).toEqual([]);
    expect(serializeComment(doc)).not.toContain(source);
  });
  it('retains safe links and treats HTML as inert text', () => {
    const doc = commentDocument(
      '[Link](https://example.invalid) <script>alert(1)</script>'
    );
    const links = [];
    doc.descendants(node =>
      links.push(
        ...node.marks
          .filter(mark => mark.type.name === 'link')
          .map(mark => mark.attrs.href)
      )
    );
    expect(links).toContain('https://example.invalid');
    expect(doc.textContent).toContain('<script>');
  });
  it('builds a multipart body with binary image files and stable ownership keys', () => {
    const file = new File(['synthetic binary'], 'print.png', {
      type: 'image/png',
    });
    const form = commentFormData({
      body: `![Print](comment-image:${key})`,
      images: [{ key, file }],
    });
    expect(form.get('comment[body]')).toContain(`comment-image:${key}`);
    expect(form.get('comment[body]')).not.toContain('base64');
    expect(form.get(`comment[images][${key}]`).name).toBe('print.png');
  });
  it('isolates drafts by Account, user, project, task and edited comment', () => {
    const scope = { accountId: 1, userId: 2, projectId: 3, taskId: 4 };
    const original = commentDraftKey(scope);
    ['accountId', 'userId', 'projectId', 'taskId', 'commentId'].forEach(field =>
      expect(commentDraftKey({ ...scope, [field]: 99 })).not.toBe(original)
    );
    expect(() => commentDraftKey({ ...scope, accountId: '../1' })).toThrow();
  });
});
