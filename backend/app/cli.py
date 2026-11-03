import argparse
import getpass
import sys
import time
from pathlib import Path

from alembic.config import Config
from alembic.runtime.migration import MigrationContext
from alembic.script import ScriptDirectory
from pydantic import TypeAdapter, ValidationError
from sqlalchemy.exc import OperationalError
from sqlmodel import Session, select

from app.db import engine
from app.models import GlobalRole, User
from app.routers.auth import revoke_all_user_tokens
from app.schemas import Password, Username
from app.security import hash_password

ALEMBIC_INI = Path(__file__).resolve().parent.parent / "alembic.ini"


def _read_password(from_stdin: bool) -> str:
    if from_stdin:
        password = sys.stdin.readline().rstrip("\n")
    else:
        password = getpass.getpass("Password: ")
        if getpass.getpass("Repeat password: ") != password:
            sys.exit("Passwords don't match.")
    try:
        return TypeAdapter(Password).validate_python(password)
    except ValidationError:
        sys.exit("Password must be 10 to 256 characters.")


def create_admin(username: str, password_from_stdin: bool) -> None:
    try:
        username = TypeAdapter(Username).validate_python(username)
    except ValidationError:
        sys.exit("Username must be 3 to 32 characters: letters, digits, '_', '.', '-'.")
    with Session(engine) as session:
        if session.exec(select(User).where(User.username == username)).first():
            sys.exit(f"User {username!r} already exists.")
        password = _read_password(password_from_stdin)
        session.add(
            User(username=username, password_hash=hash_password(password), role=GlobalRole.admin)
        )
        session.commit()
    print(f"Created admin {username!r}.")  # noqa: T201


def set_password(username: str, password_from_stdin: bool) -> None:
    with Session(engine) as session:
        user = session.exec(select(User).where(User.username == username)).first()
        if user is None:
            sys.exit(f"No user named {username!r}.")
        user.password_hash = hash_password(_read_password(password_from_stdin))
        user.token_version += 1
        revoke_all_user_tokens(session, user.id)
        session.add(user)
        session.commit()
    print(f"Password changed for {username!r}; their other sessions are signed out.")  # noqa: T201


def wait_for_migrations(timeout_seconds: int) -> None:
    expected_heads = set(ScriptDirectory.from_config(Config(str(ALEMBIC_INI))).get_heads())
    deadline = time.monotonic() + timeout_seconds
    while True:
        try:
            with engine.connect() as connection:
                current_heads = set(MigrationContext.configure(connection).get_current_heads())
            if current_heads == expected_heads:
                return
        # The database may still be starting; keep polling until the deadline.
        except OperationalError:
            current_heads = set()
        if time.monotonic() > deadline:
            sys.exit(
                f"Timed out waiting for migrations: database at {sorted(current_heads)}, "
                f"code expects {sorted(expected_heads)}."
            )
        time.sleep(2)


def main() -> None:
    parser = argparse.ArgumentParser(prog="python -m app.cli")
    commands = parser.add_subparsers(dest="command", required=True)

    for name, help_text in (
        ("create-admin", "Create an admin account."),
        ("set-password", "Set a user's password and sign out their sessions."),
    ):
        command = commands.add_parser(name, help=help_text)
        command.add_argument("username")
        command.add_argument(
            "--password-stdin",
            action="store_true",
            help="Read the password from the first line of stdin instead of prompting.",
        )

    wait = commands.add_parser(
        "wait-for-migrations", help="Block until the database schema matches this build."
    )
    wait.add_argument("--timeout", type=int, default=300, help="Seconds before giving up.")

    args = parser.parse_args()
    if args.command == "create-admin":
        create_admin(args.username, args.password_stdin)
    elif args.command == "set-password":
        set_password(args.username, args.password_stdin)
    else:
        wait_for_migrations(args.timeout)


if __name__ == "__main__":
    main()
