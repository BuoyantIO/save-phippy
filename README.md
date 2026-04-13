# Escape Room: Kubenapping in Amsterdam
## Phippy's Abduction on the Canals

_Are you ready to use your Kubernetes skills to solve the crime of the
cloud native century?_

_A dark deployment has settled over the canals of Amsterdam. Phippy has
vanished! A mysterious note, signed only by an “Unknown Controller,” has
been found near her last sighting—a cryptic warning tied to a corrupted
cluster. Play the ultimate cloud native escape room, a high-stakes
service mesh “abduction mystery” where Linky the Lobster, Linkerd’s
trusty mascot, is on the case._

_This virtual escape room challenges participants, Linky’s investigative
team, to use their Kubernetes and Linkerd skills to follow the traces,
find the logs, and solve the technical clues to find Phippy before her
liveness probe fails permanently. During the investigation, Phippy’s
friends will provide cryptic clues and debugging tips about her
whereabouts. Ready to dive in and help?_

## About the Escape Room

For KubeCon EU 2026 in Amsterdam, we decided to do something a little bit
different. Rather than sponsoring, we thought we'd throw a party -- a
little something to try to stir up some interest, have some fun, teach
people a little bit about Linkerd... and, critically, something that
would stand out. A forgettable party wouldn't help anyone.

We decided to host an escape room party.

Putting it all together was a lot of fun - and a _lot_ of work - and now
we're making it possible to run the escape room on your own! We hope you
enjoy it (and we hope you learn something in the process!), and we very
much look forward to hearing how everything goes for you -- just drop us
a line at marketing@buoyant.io, or find Flynn on the Linkerd or CNCF
Slacks!

## Prerequisites

Beyond standard Kubernetes tooling (`kubectl`, `helm`), the bootstrap
scripts require the
[Linkerd CLI](https://linkerd.io/2/getting-started/#step-1-install-the-cli).
The multiplayer setup (`sp-station.sh`) additionally requires
[yq](https://github.com/mikefarah/yq).

## Getting Started

There are two ways to run the escape room, but they both start by
installing the `spadmin` CLI, which you'll need to control things:

```bash
curl -O https://raw.githubusercontent.com/BuoyantIO/save-phippy/main/sp-install.sh
bash sp-install.sh
```

`sp-install.sh` will download the correct `spadmin` binary for your
system (MacOS or Linux) and install it into `$HOME/.save-phippy/bin`.
You'll need to add that directory to your `$PATH`.

## Running Just For Yourself

Once you have `spadmin`, the simplest way to run the escape room is to
use a k3d or kind cluster to run a single-player installation on your
local machine. To do this, just have your `KUBECONFIG` pointing to an
appropriate _empty_ cluster, then grab the single-player bootstrap
script:

```bash
curl -O https://raw.githubusercontent.com/BuoyantIO/save-phippy/main/sp-single.sh
bash sp-single.sh
```

This will install everything for you (which might take a bit!), including
bootstrapping the TLS certificates you'll need in `$PWD/certs`. Once
everything is installed, grab the IP address of the main Emissary
service:

```bash
IP=$(kubectl get svc -n emissary emissary \
             -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
```

and point a browser to `http://$IP/overview`!

Some notes about the single-player setup:

1. We rely on a Service of type LoadBalancer for ingress to the cluster;
   if you're using Kind, you'll need to make sure you've set up support
   for LoadBalancers.

2. This setup uses self-signed certificates everywhere, so you'll have to
   click past the scary browser warnings.

3. In multiplayer mode (see below) your access to your cluster is sharply
   restricted to make the game more interesting. In singleplayer mode, we
   don't do that... so don't cheat! 🙂

## Running a Multiplayer Installation

Things are a little different if you want to set things up so that
multiple players can compete! (This is how we did things in Amsterdam.)
For a multiplayer installation, you'll be running multiple clusters:

1. A single _panopticon_[^1] cluster that manages the multiplayer aspect of
   the game and shows the leaderboard
2. One additional _station cluster_ per team that will be playing
3. A bunch of certificates to protect communications between all the
   clusters[^2].

[^1]: From the Greek panoptes, “all-seeing”, originally coined by one
    Jeremy Bentham in an 18th-century prison design(!) –
    https://en.wikipedia.org/wiki/Panopticon,
    https://en.wikipedia.org/wiki/Argus_Panoptes

[^2]: Linkerd is part of the game, so we need players to be able to
    change the Linkerd configuration, which means that we can't use
    Linkerd multicluster for this.

Here's how it's done.

### 1. Setting Up

As before, you'll need `spadmin`, but this time you'll need the
multiplayer setup script:

```bash
curl -O https://raw.githubusercontent.com/BuoyantIO/save-phippy/main/sp-multi.sh
bash sp-multi.sh
```

This will install two extra scripts in `$HOME/.save-phippy/bin`:

- `sp-panopticon.sh` is a shell script that sets up a cluster to be the panopticon
- `sp-station.sh` is a shell script that sets up a cluster to be a station cluster

### 2. Initializing the Panopticon

You need to initialize the panopticon first, because you'll need the IP
address of its Emissary to do everything else.

Start, as always, by your KUBECONFIG point to an _empty_ cluster, then:

```bash
bash $HOME/.save-phippy/bin/sp-panopticon.sh
```

This will install Emissary, Linkerd, and Linkerd Viz, and the panopticon
code. It'll also create a `certs` directory in your current directory
with the certs you'll need.

Once it's done (which might take a bit!), you'll grab the panopticon's IP
address for use when you add station clusters:

```bash
IP=$(kubectl get svc -n emissary emissary \
             -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
```

#### A Note on Certificates

`cert bootstrap` creates its own self-signed CA certificate. This is
simple because it works in all cases, and annoying because it'll require
people to click through scary warnings to access the escape room.

If you want the panopticon to use a certificate from a trusted CA, you
can replace `certs/panopticon.crt` and `certs/panopticon.key` with a
certificate of your choice. Sadly, it's not really supported at present
to have stations use certificates from a different CA.

### 3. Initializing Station Clusters

From this point forward, `spadmin` will usually be talking to the
panopticon to get things done. To let it know where the panopticon is,
it's simplest to set two environment variables:

```bash
export CAPERD_URL=https://$IP/
export CAPERD_SERVER_NAME=$IP
```

Then, for each cluster you want to set up as a station:

1. Set up your KUBECONFIG to point to an empty cluster which will become
   a station cluster.

2. Run `bash $HOME/.save-phippy/bin/sp-station.sh`.

   This will install everything the station cluster needs and make the
   cluster available for the panopticon to assign to a team.

You can add new clusters at any point, so if you have a new team show up,
you can spin up a new cluster for them on the fly.

**NOTE:** Each cluster uses a single LoadBalancer Service and a PV. Each
cluster's LoadBalancer must be reachable by the players and by the
panopticon.

### 4. Registering Teams

This is easy: whoever wants to play, run

```bash
spadmin team register $teamName
```

(To unregister a team, use `spadmin team delete $teamName`.)

### 5. Provisioning

When you're ready to get started - or at any point later - run

```bash
spadmin provision [$teamName]
```

to assign teams to clusters and let them start playing. If you give a
team name, only that one team will be provisioned; if you leave the name
off, all teams will be assigned to clusters (assuming that you have
enough available clusters!).

(To deprovision a cluster, make sure that any team using the cluster has
been deleted, then you can `spadmin cluster delete $clusterName` or
`spadmin cluster reset $clusterName`.)

### 6. Starting the Game

Tell the teams to point a browser at `https://$IP/start` -- they'll enter
their team name, and Linky will walk them through how to start playing!

While the game is running, going to `https://$IP/` will show the
leaderboard.

### 7. Supporting Multiple Gamerunners

If you're planning to run the game in any public scenario, having more
than one game admin (gamerunner) can be very helpful.

To do that, every other gamerunner should install `spadmin` and use it to
create a certificate signing request for themselves:

```bash
spadmin cert csr
```

This will create a private key in $USER.key and a certificate signing
request in `$USER.csr`. (You can override the username if needed; see
`spadmin cert csr --help`.)

The other gamerunners will then get their CSRs to the gamerunner who
originally ran `cert bootstrap`. CSRs are safe to share (including
sharing over any network), so no special precautions are necessary here.
The gamerunner who ran `cert bootstrap` then needs to sign these CSRs to
turn them into real user certificates:

```bash
spadmin cert sign `$USER.csr`
```

That will create a real user certificate in `$USER.crt`. This should be
sent to the gamerunner who sent in the CSR (again, it's safe to do this).
