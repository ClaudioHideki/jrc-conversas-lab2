"""One protected Docker build on an exclusive hosted CI runner. Never publishes."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

from jrc_ag_guarded_frontend_build import ROOT, authorize, git, no_other_vite_build, node_heap_mib, resource_reason, sample

BUILDKIT_IMAGE = 'mirror.gcr.io/moby/buildkit:v0.33.1@sha256:98cc6a3fc46220d00f8224ae483f3274fc874e9be8d7dd1e2e2c5481209228b5'


def identity(env):
    sha = env.get('SOURCE_SHA', '')
    authorize(env, sha)
    if env.get('COMPONENT') != 'app' or env.get('GITHUB_REPOSITORY') != 'ClaudioHideki/jrc-conversas-lab2':
        raise RuntimeError('Only the owned LAB2 application candidate is allowed')
    if env.get('IMAGE') != 'claudiohideki/jrc-conversas-lab2':
        raise RuntimeError('Unexpected image namespace')
    run, attempt = env.get('GITHUB_RUN_ID', ''), env.get('GITHUB_RUN_ATTEMPT', '')
    if not run.isdecimal() or attempt != '1':
        raise RuntimeError('Exclusive first attempt required')
    name = f'jrc-ag-image-{run}-{attempt}'
    if env.get('JRC_AG_BUILDER') != name:
        raise RuntimeError('Builder must belong to this exact disposable job')
    return sha, name, f'buildx_buildkit_{name}0'


def inspect(container):
    return json.loads(subprocess.check_output(['docker', 'inspect', container], text=True))[0]


def execute():
    sha, builder, container = identity(os.environ)
    if Path(os.environ['GITHUB_WORKSPACE']).resolve() != ROOT or git('rev-parse', 'HEAD') != sha:
        raise RuntimeError('Exact source checkout required')
    subprocess.run(['git', 'diff', '--exit-code'], cwd=ROOT, check=True)
    no_other_vite_build()
    owned = inspect(container)
    if owned['Name'] != '/' + container or owned['Config']['Image'] != BUILDKIT_IMAGE or not owned['State']['Running']:
        raise RuntimeError('Owned pinned BuildKit container is not running')
    initial = sample()
    reason = resource_reason(initial['disk_free'], initial['ram_available'], starting=True)
    if reason:
        print(json.dumps({'started': False, 'reason': reason, 'resources': initial}))
        return 1
    output = Path(os.environ['RUNNER_TEMP']) / ('ag-image-' + sha)
    output.mkdir()
    image = f"ghcr.io/{os.environ['IMAGE']}:sha-{sha}"
    command = ['docker', 'buildx', 'build', '--builder', builder, '--load', '--platform', 'linux/amd64',
               '--file', 'docker/Dockerfile', '--build-arg', f'GIT_SHA={sha}', '--tag', image,
               '--build-arg', f'NODE_OPTIONS=--max-old-space-size={node_heap_mib(initial["ram_available"])} --openssl-legacy-provider',
               '--label', f'org.opencontainers.image.revision={sha}', '--label',
               'org.opencontainers.image.source=https://github.com/ClaudioHideki/jrc-conversas-lab2',
               '--provenance=false', '--progress=plain', '--metadata-file', str(output / 'metadata.json'), '.']
    result = {'sha': sha, 'image': image, 'publication': False, 'started': False, 'build_passed': False,
              'initial': initial, 'disk_min': initial['disk_free'], 'ram_min': initial['ram_available']}
    process = None
    start = time.monotonic()
    try:
        current = sample()
        reason = resource_reason(current['disk_free'], current['ram_available'], starting=True)
        if reason:
            raise RuntimeError(reason)
        with (output / 'build.log').open('x', encoding='utf8') as log:
            process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            result['started'] = True
            while process.poll() is None:
                current = sample()
                result['disk_min'] = min(result['disk_min'], current['disk_free'])
                result['ram_min'] = min(result['ram_min'], current['ram_available'])
                reason = resource_reason(current['disk_free'], current['ram_available'])
                if reason or time.monotonic() - start > 3600:
                    raise RuntimeError(reason or 'owned_image_build_timeout')
                time.sleep(0.5)
            result['exit_code'] = process.wait()
        if result['exit_code'] != 0:
            raise RuntimeError('Docker build failed; publication is blocked')
        current = sample()
        reason = resource_reason(current['disk_free'], current['ram_available'])
        if reason:
            raise RuntimeError(reason)
        result['disk_min'] = min(result['disk_min'], current['disk_free'])
        result['ram_min'] = min(result['ram_min'], current['ram_available'])
        result['build_passed'] = True
    except BaseException as error:
        result['failure'] = str(error)
        if process is not None and process.poll() is None:
            if os.getpgid(process.pid) != process.pid:
                raise RuntimeError('Owned process group identity changed') from error
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=10)
            result['stopped_owned_build_client'] = True
        # Only the builder just created on this hosted VM; never Windows Docker/WSL or shared services.
        if inspect(container)['Id'] != owned['Id']:
            raise RuntimeError('Owned builder identity changed; no container stopped') from error
        subprocess.run(['docker', 'stop', '--time', '10', container], check=True, stdout=subprocess.DEVNULL)
        result['stopped_owned_disposable_builder'] = True
    finally:
        result['final'] = sample()
        result['seconds'] = round(time.monotonic() - start, 2)
        (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps(result))
    return 0 if result['build_passed'] else 1


if __name__ == '__main__':
    if sys.argv[1:] != ['--execute']:
        print(json.dumps({'started': False, 'inspection_only': True}))
    else:
        sys.exit(execute())
