#!/usr/bin/env python3
import argparse
import copy
import sys
import xml.etree.ElementTree as ET

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
SPARKLE = f"{{{SPARKLE_NS}}}"
ET.register_namespace("sparkle", SPARKLE_NS)


def parse_appcast(path):
    try:
        return ET.parse(path)
    except ET.ParseError as error:
        raise SystemExit(f"Could not parse appcast XML at {path}: {error}") from error


def channel_element(tree):
    channel = tree.getroot().find("channel")
    if channel is None:
        raise SystemExit("Appcast is missing an rss/channel element.")
    return channel


def item_version(item):
    element = item.find(f"{SPARKLE}version")
    return element.text.strip() if element is not None and element.text else ""


def item_channel(item):
    element = item.find(f"{SPARKLE}channel")
    return element.text.strip() if element is not None and element.text else ""


def item_url(item):
    enclosure = item.find("enclosure")
    return enclosure.get("url", "") if enclosure is not None else ""


def find_item(channel, expected_url):
    for item in channel.findall("item"):
        if item_url(item) == expected_url:
            return item
    raise SystemExit(f"Appcast is missing expected enclosure URL: {expected_url}")


def validate_item(item, expected_url, expected_channel, expected_version=None):
    actual_url = item_url(item)
    actual_channel = item_channel(item)
    actual_version = item_version(item)
    if actual_url != expected_url:
        raise SystemExit(f"Expected enclosure URL {expected_url}, found {actual_url or '<missing>'}.")
    if actual_channel != expected_channel:
        expected_label = expected_channel or "<stable/default>"
        actual_label = actual_channel or "<stable/default>"
        raise SystemExit(f"Expected appcast channel {expected_label}, found {actual_label}.")
    if expected_version is not None and actual_version != expected_version:
        raise SystemExit(f"Expected sparkle:version {expected_version}, found {actual_version or '<missing>'}.")
    if not actual_version:
        raise SystemExit("Expected appcast item is missing sparkle:version.")


def write_tree(tree, output_path):
    if hasattr(ET, "indent"):
        ET.indent(tree, space="    ")
    tree.write(output_path, encoding="utf-8", xml_declaration=True)


def command_merge(args):
    existing_tree = parse_appcast(args.existing)
    incoming_tree = parse_appcast(args.incoming)
    existing_channel = channel_element(existing_tree)
    incoming_channel = channel_element(incoming_tree)
    incoming_item = find_item(incoming_channel, args.expected_url)
    validate_item(incoming_item, args.expected_url, args.expected_channel)

    incoming_version = item_version(incoming_item)
    incoming_channel_name = item_channel(incoming_item)
    for item in list(existing_channel.findall("item")):
        same_url = item_url(item) == args.expected_url
        same_version_and_channel = (
            item_version(item) == incoming_version and item_channel(item) == incoming_channel_name
        )
        if same_url or same_version_and_channel:
            existing_channel.remove(item)

    insert_index = 0
    for index, child in enumerate(list(existing_channel)):
        if child.tag == "item":
            insert_index = index
            break
        insert_index = index + 1
    existing_channel.insert(insert_index, copy.deepcopy(incoming_item))
    write_tree(existing_tree, args.output)


def command_verify(args):
    tree = parse_appcast(args.appcast)
    item = find_item(channel_element(tree), args.expected_url)
    validate_item(item, args.expected_url, args.expected_channel, args.expected_version)


def command_version(args):
    tree = parse_appcast(args.appcast)
    item = find_item(channel_element(tree), args.expected_url)
    validate_item(item, args.expected_url, args.expected_channel)
    print(item_version(item))


def numeric_version(value, label):
    if not value.isdigit():
        raise SystemExit(f"{label} sparkle:version must contain digits only, found {value or '<missing>'}.")
    return int(value)


def command_assert_newer(args):
    existing_tree = parse_appcast(args.existing)
    incoming_tree = parse_appcast(args.incoming)
    incoming_item = find_item(channel_element(incoming_tree), args.expected_url)
    incoming_version = item_version(incoming_item)
    incoming_number = numeric_version(incoming_version, "Incoming")

    existing_versions = [
        item_version(item)
        for item in channel_element(existing_tree).findall("item")
    ]
    if not existing_versions:
        return

    highest_existing = max(
        numeric_version(version, "Existing")
        for version in existing_versions
    )
    if incoming_number <= highest_existing:
        raise SystemExit(
            "Incoming sparkle:version "
            f"{incoming_version} must be greater than the existing maximum {highest_existing}. "
            "Sparkle refuses to install application downgrades."
        )


def main():
    parser = argparse.ArgumentParser(description="Merge and verify Sparkle appcast items.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    merge = subparsers.add_parser("merge")
    merge.add_argument("--existing", required=True)
    merge.add_argument("--incoming", required=True)
    merge.add_argument("--output", required=True)
    merge.add_argument("--expected-url", required=True)
    merge.add_argument("--expected-channel", default="")
    merge.set_defaults(func=command_merge)

    verify = subparsers.add_parser("verify")
    verify.add_argument("--appcast", required=True)
    verify.add_argument("--expected-url", required=True)
    verify.add_argument("--expected-channel", default="")
    verify.add_argument("--expected-version")
    verify.set_defaults(func=command_verify)

    version = subparsers.add_parser("version")
    version.add_argument("--appcast", required=True)
    version.add_argument("--expected-url", required=True)
    version.add_argument("--expected-channel", default="")
    version.set_defaults(func=command_version)

    assert_newer = subparsers.add_parser("assert-newer")
    assert_newer.add_argument("--existing", required=True)
    assert_newer.add_argument("--incoming", required=True)
    assert_newer.add_argument("--expected-url", required=True)
    assert_newer.set_defaults(func=command_assert_newer)

    args = parser.parse_args()
    try:
        args.func(args)
    except BrokenPipeError:
        sys.exit(1)


if __name__ == "__main__":
    main()
