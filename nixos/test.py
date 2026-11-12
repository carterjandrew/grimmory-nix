start_all()

machine.succeed(f'test "$(uname -m)" = "{expected_arch}"')
machine.wait_for_unit("mysql.service")
machine.wait_for_unit("grimmory-database-setup.service")
machine.wait_for_unit("grimmory.service")
machine.wait_until_succeeds("curl --fail --silent http://127.0.0.1:7777/api/v1/healthcheck")
machine.wait_until_succeeds(
    "journalctl --unit grimmory.service --no-pager | "
    "grep --fixed-strings --quiet 'Native libraries, PDFium: loaded'"
)
machine.succeed("curl --fail --silent http://127.0.0.1:7777/ | grep --quiet '<app-root'")
machine.fail("curl --fail --silent --connect-timeout 1 http://127.0.0.1:6060/api/v1/healthcheck")
machine.succeed("test -d /var/lib/grimmory/data")
machine.succeed("test -d /var/lib/grimmory/books")
machine.succeed("test -d /var/lib/grimmory/bookdrop")

machine.succeed("systemctl restart grimmory.service")
machine.wait_until_succeeds("curl --fail --silent http://127.0.0.1:7777/api/v1/healthcheck")
