"""Real HTTP regression on the owned internal network; no application image build."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import urllib.error
from unittest.mock import patch
import guard

IMAGE = "docker.io/library/node:24.22.3-alpine3.24@sha256:116b800c3754b440ee0aa3ed2f20f5bf3d99a554bfd9adeea09ea8017f6e85f5"
NAME = "jrc-http-regression-" + os.environ["GITHUB_RUN_ID"]
WEB = NAME + "-web"
OUT = Path(os.environ["RUNNER_TEMP"]) / "http-network-regression.json"
assert os.environ["RUNNER_ENVIRONMENT"] == "github-hosted"
def command(args):
    r = subprocess.run(args, text=True, capture_output=True, timeout=120)
    if r.returncode:
        raise RuntimeError("Owned HTTP regression command failed")
    return r.stdout
def inspect():
    info = json.loads(command(["docker","inspect",WEB]))[0]
    assert info["Config"]["Labels"]["jrc.runtime.run"] == NAME
    return info
report = {"passed":False,"product_sha":os.environ["EXPECTED_PRODUCT_SHA"],
          "infrastructure_sha":os.environ["GITHUB_SHA"],"application_image_built":False}
created = False
try:
    command(["docker","network","create","--internal","--label","jrc.runtime.run="+NAME,NAME])
    routes = {"/app/login":"<html>JRC regression /vite/dashboard.js</html>",
              "/vite/dashboard.js":"console.log('dashboard');",
              "/vite/v3app.js":"console.log('v3app');",
              "/vite/theme.css":"body{color:#123456}"}
    server = "const routes="+json.dumps(routes)+";require('http').createServer((q,s)=>{s.statusCode=q.url in routes?200:404;s.end(routes[q.url]||'missing')}).listen(3000,'0.0.0.0')"
    command(["docker","run","-d","--name",WEB,"--label","jrc.runtime.run="+NAME,
             "--network",NAME,IMAGE,"node","-e",server])
    created = True
    info=inspect()
    assert not info["HostConfig"].get("Privileged") and not info["HostConfig"].get("PortBindings")
    network=json.loads(command(["docker","network","inspect",NAME]))[0]
    assert network["Internal"] and network["Labels"]["jrc.runtime.run"]==NAME
    origin=guard.internal_origin(info,NAME)
    with patch.dict(os.environ,{"http_proxy":"http://127.0.0.1:9","HTTP_PROXY":"http://127.0.0.1:9",
                                "https_proxy":"http://127.0.0.1:9","HTTPS_PROXY":"http://127.0.0.1:9",
                                "no_proxy":"","NO_PROXY":""}):
        deadline=time.monotonic()+30
        while True:
            try:
                with guard.http_open(origin+"/app/login",timeout=3) as response:
                    html=response.read()
                    assert response.status==200 and b"<html" in html.lower() and b"/vite/" in html
                break
            except (OSError,urllib.error.HTTPError):
                if time.monotonic()>=deadline:raise RuntimeError("Internal HTTP readiness failed")
                time.sleep(0.5)
        assets=[]
        for path in ["/vite/dashboard.js","/vite/v3app.js","/vite/theme.css"]:
            with guard.http_open(origin+path,timeout=5) as response:
                data=response.read();expected=hashlib.sha256(routes[path].encode()).hexdigest()
                assert response.status==200 and hashlib.sha256(data).hexdigest()==expected
                assets.append({"path":path,"status":response.status,"sha256":expected})
        try:
            guard.http_open(origin+"/missing",timeout=5)
            raise AssertionError("Missing route accepted")
        except urllib.error.HTTPError as error:
            assert error.code==404
    report.update(passed=True,origin=origin,transport="owned_internal_ipv4",network_is_internal=True,
                  host_ports_published=False,login_status=200,verified_assets=assets,
                  inherited_proxies_bypassed=True,missing_route_rejected=True,
                  port_metadata_not_required=True)
finally:
    if created:
        info=inspect()
        if info["State"]["Running"]:
            command(["docker","stop","--time","10",WEB])
    OUT.write_text(json.dumps(report,indent=2))
    print(json.dumps(report))
