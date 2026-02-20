#!/usr/bin/env python3
"""Decode binary tracing logs to JSONL format."""

import argparse
import json
import struct
import sys
from pathlib import Path

EVENT_TYPES = {
    0: "start",
    1: "end",
    2: "new_object",
    3: "metadata",
    4: "operation",
    5: "subscript",
}

HEADER_FORMAT = "<Q Q I Q Q B I"
HEADER_SIZE = struct.calcsize(HEADER_FORMAT)


def decode_string(data, offset):
    length = struct.unpack_from("<I", data, offset)[0]
    offset += 4
    string_bytes = data[offset : offset + length]
    return string_bytes.decode("utf-8"), offset + length


def decode_new_object(payload):
    uid = struct.unpack_from("<Q", payload, 0)[0]
    class_name, _ = decode_string(payload, 8)
    return {"uid": str(uid), "class": class_name}


def decode_metadata(payload):
    fields = {}

    if len(payload) >= 8:
        uid = struct.unpack_from("<Q", payload, 0)[0]
        fields["uid"] = str(uid)

    if len(payload) >= 16:
        nrow = struct.unpack_from("<Q", payload, 8)[0]
        fields["nrow"] = str(nrow)

    if len(payload) >= 24:
        ncol = struct.unpack_from("<Q", payload, 16)[0]
        fields["ncol"] = str(ncol)

    if len(payload) >= 32:
        nnz = struct.unpack_from("<Q", payload, 24)[0]
        fields["nnz"] = str(nnz)

    return fields


def decode_operation_other(payload):
    # C format: input_uids[n] + class_len + class_name
    # - n * 8 bytes of input UIDs (uint64_t array)
    # - 4 bytes: class_len (uint32_t)
    # - class_len bytes: class_name (UTF-8 string)

    if len(payload) < 13:  # Minimum: 1 uid (8) + class_len (4) + 1 char = 13
        return {"raw_data": payload.hex()}

    payload_len = len(payload)

    # Try n_inputs from 1 to 10
    for n in range(1, 11):
        uid_bytes = 8 * n
        remaining = payload_len - uid_bytes
        if remaining < 4:  # Need at least 4 bytes for class_len
            continue

        class_len = struct.unpack_from("<I", payload, uid_bytes)[0]
        total_needed = uid_bytes + 4 + class_len
        if total_needed == payload_len:
            input_uids = []
            for i in range(n):
                uid = struct.unpack_from("<Q", payload, 8 * i)[0]
                input_uids.append(str(uid))

            class_name = payload[uid_bytes + 4 : uid_bytes + 4 + class_len].decode(
                "utf-8", errors="replace"
            )
            return {
                "num_inputs": n,
                "input_uids": input_uids,
                "output_class": class_name,
            }

    return {
        "num_inputs": -1,
        "input_uids": [],
        "raw_data": payload.hex(),
    }


def decode_operation(payload):
    # C format: input_uids[n] + output_count + output_uids[m]
    # - n * 8 bytes of input UIDs (uint64_t array)
    # - 4 bytes: output_count (uint32_t)
    # - output_count * 8 bytes: output UIDs (uint64_t array)

    if len(payload) < 12:
        return {"raw_data": payload.hex()}

    payload_len = len(payload)

    for n in range(1, 11):
        input_bytes = 8 * n
        remaining = payload_len - input_bytes
        if remaining < 4:
            continue

        output_count = struct.unpack_from("<I", payload, input_bytes)[0]
        total_needed = input_bytes + 4 + (8 * output_count)
        if total_needed == payload_len:
            input_uids = []
            for i in range(n):
                uid = struct.unpack_from("<Q", payload, 8 * i)[0]
                input_uids.append(str(uid))

            output_uids = []
            offset = input_bytes + 4
            for i in range(output_count):
                uid = struct.unpack_from("<Q", payload, offset + 8 * i)[0]
                output_uids.append(str(uid))

            return {
                "input_uids": input_uids,
                "output_uids": output_uids,
            }

    return {
        "input_uids": [],
        "raw_data": payload.hex(),
    }


def decode_subscript(payload):
    # C format: input_uid (8) + row_count (4) + row_indices[n*4] + col_count (4) + col_indices[m*4]
    # - 8 bytes: input_uid (uint64_t)
    # - 4 bytes: row_count (uint32_t)
    # - row_count * 4 bytes: row_indices (int32_t array, NA_INTEGER = -2147483648 preserved)
    # - 4 bytes: col_count (uint32_t)
    # - col_count * 4 bytes: col_indices (int32_t array, NA_INTEGER = -2147483648 preserved)

    if len(payload) < 16:  # Minimum: input_uid (8) + row_count (4) + col_count (4) = 16
        return {"raw_data": payload.hex()}

    offset = 0

    input_uid = struct.unpack_from("<Q", payload, offset)[0]
    offset += 8

    row_count = struct.unpack_from("<I", payload, offset)[0]
    offset += 4

    row_indices = []
    for _ in range(row_count):
        row_val = struct.unpack_from("<i", payload, offset)[0]
        offset += 4
        row_indices.append(row_val)

    col_count = struct.unpack_from("<I", payload, offset)[0]
    offset += 4

    col_indices = []
    for _ in range(col_count):
        col_val = struct.unpack_from("<i", payload, offset)[0]
        offset += 4
        col_indices.append(col_val)

    result = {
        "input_uid": str(input_uid),
        "row_idx_count": row_count,
        "col_idx_count": col_count,
    }

    if row_count > 0:
        result["row_indices"] = row_indices

    if col_count > 0:
        result["col_indices"] = col_indices

    return result


def decode_record(header, payload):
    fields = struct.unpack(HEADER_FORMAT, header)
    gsn, timestamp, thread_id, span_id, parent_id, event_type, payload_size = fields
    record = {
        "gsn": str(gsn),
        "timestamp": str(timestamp),
        "thread_id": str(thread_id),
        "span_id": str(span_id),
        "parent_id": str(parent_id),
        "event_type": EVENT_TYPES.get(event_type, f"unknown_{event_type}"),
    }
    if event_type == 2:
        obj = decode_new_object(payload)
        record["uid"] = obj["uid"]
        record["class"] = obj["class"]
    elif event_type == 3:
        obj = decode_metadata(payload)
        if "uid" in obj:
            record["uid"] = obj["uid"]
        if "nrow" in obj:
            record["nrow"] = obj["nrow"]
        if "ncol" in obj:
            record["ncol"] = obj["ncol"]
        if "nnz" in obj:
            record["nnz"] = obj["nnz"]
    elif event_type == 4:
        obj = decode_operation(payload)
        record["input_uids"] = obj["input_uids"]
        record["output_uids"] = obj["output_uids"]
    elif event_type == 5:
        obj = decode_subscript(payload)
        record["input_uid"] = obj["input_uid"]
        record["row_idx_count"] = obj["row_idx_count"]
        record["col_idx_count"] = obj["col_idx_count"]
        if "row_indices" in obj:
            record["row_indices"] = obj["row_indices"]
        if "col_indices" in obj:
            record["col_indices"] = obj["col_indices"]
    elif event_type == 0:
        if payload:
            payload_str = payload.decode("utf-8", errors="replace")
            parts = payload_str.split("\x00")
            record["op_name"] = parts[0] if len(parts) > 0 else ""
            record["call_site"] = parts[1] if len(parts) > 1 else ""
    elif event_type == 1:
        pass

    return record


def decode_log_file(log_path):
    with open(log_path, "rb") as f:
        while True:
            header = f.read(HEADER_SIZE)
            if not header:
                break
            if len(header) < HEADER_SIZE:
                print(
                    f"Warning: truncated header at position {f.tell()}", file=sys.stderr
                )
                break
            payload_size = struct.unpack(HEADER_FORMAT, header)[6]
            payload = f.read(payload_size)
            if len(payload) < payload_size:
                print(
                    f"Warning: truncated payload at position {f.tell()}",
                    file=sys.stderr,
                )
                break
            record = decode_record(header, payload)
            print(json.dumps(record))


def main():
    parser = argparse.ArgumentParser(
        description="Decode binary tracing logs to JSONL format"
    )
    parser.add_argument("log_file", type=Path, help="Path to the binary log file")
    args = parser.parse_args()
    if not args.log_file.exists():
        print(f"Error: File not found: {args.log_file}", file=sys.stderr)
        sys.exit(1)
    decode_log_file(args.log_file)


if __name__ == "__main__":
    main()
