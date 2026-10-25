import Base
import ../src/tui/model.bend as M
import ../src/tui/view.bend as V

# One recorded frame: two accounts, a live daemon, one log line. The clock is
# 2026-10-23T09:00:00Z (1792746000), the zone UTC (offset 86400, biased).

def snap() -> M.Snap:
  M.Snap{1792746000, 86400, M.Hdr{"cswap-bend 0.0.1", True{}, Some{4242}, Some{9000}, Some{60}, Some{1792746045}},
    [M.Acct{"1", "a@x.test", "work", "personal", True{}, False{}, [M.Win{"5h", Some{4700}, Some{1792753980}}, M.Win{"7d", Some{6250}, Some{1792846800}}], Some{30}, ""},
     M.Acct{"2", "b@x.test", "", "Acme", False{}, False{}, [M.Win{"5h", Some{9200}, Some{1792749000}}, M.Win{"7d", Some{6300}, None{}}], Some{400}, ""}],
    ["09:00:00  info tick no-action"]}

def frame_plain() -> {V.frame(snap(), M.View{80, False{}}) == "cswap tui  cswap-bend 0.0.1\n● auto-switch LIVE · threshold 90% · every 60s · next poll in 45s · pid 4242\n\n 1  work (a@x.test)  [personal]   ● active\n    5h ━━━━━━━━━━━━━━─────────────┃──  47%  resets 2h 13m · 11:13\n    7d ━━━━━━━━━━━━━━━━━━╸────────┃──  62%  resets 1d 4h · Oct 24 13:00\n\n 2  b@x.test  [Acme]   5h 92% · 7d 63%\n\nnext best  2 b@x.test · 8% free\n\ndaemon log\n  09:00:00  info tick no-action" : String}:
  {==}

# Narrower than the content: lines end in an ellipsis, rows drop the clock time.
def frame_narrow() -> {V.frame(snap(), M.View{40, False{}}) == "cswap tui  cswap-bend 0.0.1\n● auto-switch LIVE · threshold 90% · ev…\n\n 1  work (a@x.test)  [personal]   ● act…\n    5h ━━━━━╸─────┃  47%  resets 2h 13m\n    7d ━━━━━━━╸───┃  62%  resets 1d 4h\n\n 2  b@x.test  [Acme]   5h 92% · 7d 63%\n\nnext best  2 b@x.test · 8% free\n\ndaemon log\n  09:00:00  info tick no-action" : String}:
  {==}

def stopped() -> {V.frame(M.Snap{1792746000, 86400, M.Hdr{"v", False{}, Some{4242}, None{}, None{}, Some{1792746045}}, [], []}, M.View{80, False{}}) == "cswap tui  v\n○ auto-switch STOPPED\n\nNo managed accounts yet. Add one with: cswap add\n\nnext best  none (no other account has a reading)\n\ndaemon log\n  no daemon log yet" : String}:
  {==}

def next_best_picks_most_free() -> {V.next_best([M.Acct{"1", "a", "", "p", True{}, False{}, [], None{}, ""}, M.Acct{"2", "b", "", "p", False{}, False{}, [M.Win{"5h", Some{9000}, None{}}], None{}, ""}, M.Acct{"3", "c", "", "p", False{}, False{}, [M.Win{"5h", Some{2000}, None{}}, M.Win{"Opus", Some{5000}, None{}}], None{}, ""}, M.Acct{"4", "d", "", "p", False{}, True{}, [M.Win{"5h", Some{100}, None{}}], None{}, ""}], None{}) == Some{V.Best{"3", "c", 5000}} : Maybe<&2, V.Best>}:
  {==}

def next_best_first_wins_ties() -> {V.next_best([M.Acct{"2", "b", "", "p", False{}, False{}, [M.Win{"5h", Some{5000}, None{}}], None{}, ""}, M.Acct{"3", "c", "", "p", False{}, False{}, [M.Win{"7d", Some{5000}, None{}}], None{}, ""}], None{}) == Some{V.Best{"2", "b", 5000}} : Maybe<&2, V.Best>}:
  {==}
