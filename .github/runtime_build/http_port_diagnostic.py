"""Reproduce the existing HTTP port lookup without building an application image."""
import json, os, subprocess, time, urllib.request
from pathlib import Path

IMAGE = "docker.io/library/node:24.22.3-alpine3.24@sha256:116b800c3754b440ee0aa3ed2f20f5bf3d99a554bfd9adeea09ea8017f6e85f5"
NAME = "jrc-http-diag-" + os.environ["GITHUB_RUN_ID"]
OUT = Path(os.environ["RUNNER_TEMP"]) / "http-port-diagnostic"
OUT.mkdir()
assert os.environ["RUNNER_ENVIRONMENT"] == "github-hosted"
def command(args):
    r = subprocess.run(args, text=True, capture_output=True, timeout=120)
    if r.returncode:
        raise RuntimeError("Owned diagnostic command failed: " + args[1])
    return r.stdout
def inspect():
    data = json.loads(command(["docker", "inspect", NAME]))[0]
    assert data["Config"]["Labels"]["jrc.http.diagnostic"] == NAME
    return data
result = {"application_image_built": False, "product_sha": os.environ["EXPECTED_PRODUCT_SHA"],
          "infrastructure_sha": os.environ["GITHUB_SHA"], "snapshots": [], "passed": False}
try:
    result["docker_version"] = json.loads(command(["docker", "version", "--format", "{{json .}}"]))
    command(["docker", "network", "create", "--internal", "--label", "jrc.http.diagnostic="+NAME, NAME])
    server = "require('http').createServer((q,s)=>{s.writeHead(200,{'Content-Type':'text/html'});s.end('<html>jrc-http-probe /vite/probe.css</html>')}).listen(3000,'0.0.0.0')"
    command(["docker", "run", "-d", "--name", NAME, "--label", "jrc.http.diagnostic="+NAME,
             "--network", NAME, "-p", "127.0.0.1::3000", IMAGE, "node", "-e", server])
    for i in range(10):
        info = inspect()
        ports = info.get("NetworkSettings", {}).get("Ports")
        entry = {"index":i, "state":{k:info["State"].get(k) for k in ["Status","Running","ExitCode","Error"]},
                 "exposed_ports":info["Config"].get("ExposedPorts"),
                 "host_port_bindings":info["HostConfig"].get("PortBindings"), "network_ports":ports}
        try:
            entry["old_host_port"] = info["NetworkSettings"]["Ports"]["3000/tcp"][0]["HostPort"]
        except (KeyError,TypeError,IndexError) as error:
            entry["old_lookup_error"] = {"type":type(error).__name__,"key":str(error)}
        result["snapshots"].append(entry)
        time.sleep(0.5)
    check = "fetch('http://127.0.0.1:3000/app/login').then(async r=>{const b=await r.text();if(r.status!==200||!b.includes('jrc-http-probe'))process.exit(1);console.log(JSON.stringify({status:r.status,body:b}))}).catch(()=>process.exit(1))"
    result["actual_internal_http"] = json.loads(command(["docker","exec",NAME,"node","-e",check]))
    info = inspect()
    result["network_is_internal"] = json.loads(command(["docker","network","inspect",NAME]))[0]["Internal"]
    result["container_logs"] = command(["docker","logs",NAME])
    result["host_lookup_available"] = all("old_host_port" in s for s in result["snapshots"])
    result["passed"] = True
finally:
    try:
        info = inspect()
        if info["State"]["Running"]:
            command(["docker","stop","--time","10",NAME])
    except Exception as error:
        result["owned_stop_error"] = type(error).__name__
    (OUT/"diagnostic.json").write_text(json.dumps(result,indent=2))
    print(json.dumps(result))
