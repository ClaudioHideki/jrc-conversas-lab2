"""Read-only verification of fixed-Scout and PID-1 native evidence."""
import json

PRODUCT = "d11c879a3d6e27499e1aea45736797a6e913b829"
PROBE = "9131d1784a8256fed273b15f6f7b18389223612e"
RUN = 43321695922
ARTIFACTS = {
    13989828801: ("scout-alpine-" + PROBE, "8e64bd13f3f35172cdf53fe5dfb6f5f653d5bb7256e325261d11c0eaede6013d"),
    13990772444: ("scout-native-" + PROBE, "c56dd6521874862319a76550ff8fa0fa526e70b40c03c6d446d4ee4dd54a2ed7"),
}


def payloads(alpine, pid_one, native, require):
    require(alpine["passed"] is True and alpine["ruby"] == "3.4.12" and alpine["patchlevel"] == 148
            and alpine["alpine"] == "3.24.4" and alpine["platform"] == "x86_64-linux-musl",
            "Scout Alpine runtime differs")
    require(alpine["scout"] == "5.7.0" and alpine["allocations_enabled"] is True
            and type(alpine["allocations_delta"]) is int and alpine["allocations_delta"] >= 2000,
            "Fixed Scout instrumentation missing")
    require(alpine["application_image_built"] is False, "Focused evidence cannot claim application image")
    require(pid_one["passed"] is True and type(pid_one["pid"]) is int and pid_one["pid"] == 1
            and pid_one["examples"] == 15 and pid_one["failures"] == 0 and pid_one["pending"] == 0
            and "actual_container_pid_one" in pid_one["cases"], "Real PID 1 receipt proof missing")
    require(native["passed"] is True and native["product_sha"] == PRODUCT
            and native["scout_version"] == "5.7.0" and native["allocation_monitoring"] is True
            and native["postgres_redis_receipts_equal"] is True, "Native Scout/receipt identity differs")
    require(type(native["actual_sidekiq_pid"]) is int and native["actual_sidekiq_pid"] > 0
            and type(native["verifier_pid"]) is int and native["verifier_pid"] > 0
            and native["actual_sidekiq_pid"] != native["verifier_pid"], "Separate real worker missing")


def verify(gh, require, archive, member, rspec, apt):
    require(gh.api("/git/ref/heads/ci/runtime-scout-probe-fix-20261112")["object"]["sha"] == PROBE,
            "Approved probe ref moved")
    r = gh.api("/actions/runs/" + str(RUN))
    require(r["head_sha"] == PROBE and r["run_attempt"] == 1 and r["status"] == "completed"
            and r["conclusion"] == "success" and r["head_branch"] == "ci/runtime-scout-probe-fix-20261112",
            "Focused native run not approved")
    jobs = gh.api("/actions/runs/" + str(RUN) + "/attempts/1/jobs?per_page=100")
    require(jobs["total_count"] == len(jobs["jobs"]) == 2
            and {(j["id"], j["name"]) for j in jobs["jobs"]} ==
            {(131543711051, "focused-alpine"), (131544002620, "native-runtime")}, "Focused job identity differs")
    for j in jobs["jobs"]:
        require(j["head_sha"] == PROBE and j["run_attempt"] == 1 and j["status"] == "completed"
                and j["conclusion"] == "success" and j["runner_id"] and j["steps"]
                and not any(s["conclusion"] in ("failure", "cancelled", "timed_out") for s in j["steps"]),
                "Focused job did not execute successfully")
    arts = gh.api("/actions/runs/" + str(RUN) + "/artifacts?per_page=100")
    require(arts["total_count"] == len(arts["artifacts"]) == 2
            and {a["id"] for a in arts["artifacts"]} == set(ARTIFACTS), "Focused artifacts missing")
    zs = {}
    for a in arts["artifacts"]:
        name, checksum = ARTIFACTS[a["id"]]
        require(a["name"] == name and a["digest"] == "sha256:" + checksum and not a["expired"]
                and a["workflow_run"]["id"] == RUN and a["workflow_run"]["head_sha"] == PROBE,
                "Focused artifact identity or digest differs")
        zs[a["id"]] = archive(gh.download(a["archive_download_url"]), checksum)
    az, nz = zs[13989828801], zs[13990772444]
    alpine = json.loads(member(az, "scout-alpine.json"))
    pid_one = json.loads(member(az, "pid-one.json"))
    native = json.loads(member(nz, "receipt-native.json"))
    payloads(alpine, pid_one, native, require)
    rspec(json.loads(member(nz, "runtime-rspec.json")), 16)
    old = member(az, "scout-old.log").decode(errors="replace")
    require("incompatible-pointer-types" in old and "allocations.c" in old,
            "Original native compilation failure was not reproduced")
    log = gh.download(gh.base + "/actions/jobs/131544002620/logs").decode(errors="replace")
    mirror = apt(log)
    return {"passed": True, "product_sha": PRODUCT, "probe_sha": PROBE, "run_id": RUN,
            "alpine_scout_570_native": True, "actual_pid_one": True,
            "real_sidekiq_postgresql_redis": True, "mirror": mirror,
            "artifacts": [{"id": key, "sha256": v[1]} for key, v in ARTIFACTS.items()],
            "external_telemetry_homologated": False}
