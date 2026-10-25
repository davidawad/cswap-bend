import Base
import ../src/clock.bend as Clock

# Seconds to text.
def fmt_epoch() -> {Clock.iso8601_utc(0) == "1970-01-01T00:00:00Z" : String}:
  {==}

def fmt_ref() -> {Clock.iso8601_utc(1793350800) == "2026-10-30T09:00:00Z" : String}:
  {==}

def fmt_offset() -> {Clock.iso8601_offset(1793350800) == "2026-10-30T09:00:00+00:00" : String}:
  {==}

def fmt_leap() -> {Clock.iso8601_utc(1709251199) == "2024-02-29T23:59:59Z" : String}:
  {==}

def fmt_2100() -> {Clock.iso8601_utc(4107542400) == "2100-03-01T00:00:00Z" : String}:
  {==}

# Text to seconds, every form the reference writes.
def parse_offset() -> {Clock.parse_iso8601("2026-10-30T09:00:00+00:00") == Some{1793350800} : Maybe<&2, U32>}:
  {==}

def parse_z() -> {Clock.parse_iso8601("2026-10-30T09:00:00Z") == Some{1793350800} : Maybe<&2, U32>}:
  {==}

def parse_frac() -> {Clock.parse_iso8601("2026-10-30T09:00:00.123456+00:00") == Some{1793350800} : Maybe<&2, U32>}:
  {==}

def parse_frac_z() -> {Clock.parse_iso8601("2026-10-30T09:00:00.5Z") == Some{1793350800} : Maybe<&2, U32>}:
  {==}

def parse_neg() -> {Clock.parse_iso8601("2026-10-30T04:00:00-05:00") == Some{1793350800} : Maybe<&2, U32>}:
  {==}

def parse_pos() -> {Clock.parse_iso8601("2026-10-30T14:30:00+05:30") == Some{1793350800} : Maybe<&2, U32>}:
  {==}

def parse_naive() -> {Clock.parse_iso8601("2026-10-30T09:00:00") == Some{1793350800} : Maybe<&2, U32>}:
  {==}

def parse_epoch() -> {Clock.parse_iso8601("1970-01-01T00:00:00Z") == Some{0} : Maybe<&2, U32>}:
  {==}

def parse_leap() -> {Clock.parse_iso8601("2024-02-29T23:59:59Z") == Some{1709251199} : Maybe<&2, U32>}:
  {==}

def parse_garbage() -> {Clock.parse_iso8601("tomorrow") == None{} : Maybe<&2, U32>}:
  {==}

def parse_empty() -> {Clock.parse_iso8601("") == None{} : Maybe<&2, U32>}:
  {==}

def parse_bad_month() -> {Clock.parse_iso8601("2026-13-30T09:00:00Z") == None{} : Maybe<&2, U32>}:
  {==}

def parse_trailing() -> {Clock.parse_iso8601("2026-10-30T09:00:00Zjunk") == None{} : Maybe<&2, U32>}:
  {==}

# Round trip.
def round_trip() -> {Clock.parse_iso8601(Clock.iso8601_utc(1793350800)) == Some{1793350800} : Maybe<&2, U32>}:
  {==}
