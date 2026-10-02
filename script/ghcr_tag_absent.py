"""Refuse publication unless an authenticated GHCR lookup proves tag absence."""
import base64
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def main():
    image, sha = sys.argv[1:]
    if not re.fullmatch(r'claudiohideki/[a-z0-9._-]+', image) or not re.fullmatch(r'[0-9a-f]{40}', sha):
        raise ValueError('Invalid image or full source SHA')
    actor, github_token = os.environ['GHCR_ACTOR'], os.environ['GHCR_TOKEN']
    basic = base64.b64encode(f'{actor}:{github_token}'.encode()).decode()
    opener = urllib.request.build_opener(NoRedirect)
    query = urllib.parse.urlencode({'service': 'ghcr.io', 'scope': f'repository:{image}:pull,push'})
    request = urllib.request.Request('https://ghcr.io/token?' + query, headers={'Authorization': 'Basic ' + basic})
    with opener.open(request, timeout=30) as response:
        token_data = json.load(response)
    token = token_data.get('token') or token_data.get('access_token')
    if not isinstance(token, str) or not token:
        raise ValueError('Registry authentication did not return a token')
    request = urllib.request.Request(
        f'https://ghcr.io/v2/{image}/manifests/sha-{sha}',
        headers={'Authorization': 'Bearer ' + token, 'Accept': ', '.join([
            'application/vnd.oci.image.index.v1+json', 'application/vnd.oci.image.manifest.v1+json',
            'application/vnd.docker.distribution.manifest.list.v2+json', 'application/vnd.docker.distribution.manifest.v2+json',
        ])},
    )
    try:
        with opener.open(request, timeout=30):
            raise ValueError('Tag already exists; publication refused')
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise ValueError(f'Registry lookup returned HTTP {error.code}; absence not confirmed') from None
        payload = json.loads(error.read(1024 * 1024))
        errors = payload.get('errors')
        if not errors or any(item.get('code') != 'MANIFEST_UNKNOWN' for item in errors):
            raise ValueError('Registry did not explicitly confirm MANIFEST_UNKNOWN')
    print('Authenticated registry confirmed that the exact SHA tag is absent.')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, urllib.error.URLError, json.JSONDecodeError, TimeoutError, OSError) as error:
        # Never emit requests, headers, tokens, raw responses or credential values.
        print(f'Publication refused: {type(error).__name__}. Check tag existence, GHCR permissions and connectivity.', file=sys.stderr)
        sys.exit(1)
