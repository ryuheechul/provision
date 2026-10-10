# dev

A general purpose dev VM with no local config: `make start` goes through
[start-or-resume.sh](../bin/start-or-resume.sh), which for a missing
`config.yaml` runs `limactl start dev`, and lima resolves that to its
`default` template (currently Ubuntu, vz, 4 GiB RAM, 100 GiB disk).

lima logs a deprecation for this form - the modern equivalent is
`limactl create --name=dev template:default`.

## Usage

    make start     # create (first call downloads the image) or resume, then enter
    make debug     # same, but a fresh dev-debug instance with hostagent debug logs
    make enter     # shell into the guest
    make edit      # edit the instance's lima config
    make teardown  # stop and delete the VM

## Notes

- `.env` in this directory is gitignored.
- From inside the guest, `make host` reaches the macOS host over
  `ssh host.lima.internal`.
