---
layout: narrative
title: "Deploying a Web App on an IPv6-Only Server"
author: Emilio Mendoza
editor: Emilio Mendoza
publication-date: 2025
toc:
- Intro
- Connecting to the server
- Deploying the app
- Conclusion

---

---

## Intro
Recently, I was looking for a way to deploy a personal project. 

You're reading this blog on [GitHub Pages](https://pages.github.com/), and I love its simplicity and ease of use. But since it's a Rails app, I had to look for something a bit more beefy.

My first instinct was to use a PaaS platform — we were in the process of moving away from [Heroku](https://www.heroku.com/) at work and I decided to check the new crop of offerings that have surged in the last few years.

To be fair, I could have stuck with Heroku; after all I was fairly familiar with it given my experience at work. But at the same time, we were not satisfied with pricing and stability, so I decided to look for alternatives.

First, I tried [Render](https://render.com). It was pretty easy to get going, but as soon as I started to ingest data, I kept on running into RAM limits.

Naturally, the solution was to scale up. But I was not willing to pay for that. I was paying $27/month for 512MB of RAM in my web server and 1GB of RAM in Postgres, which was not enough for my needs and is frankly expensive considering I could barely import a fraction of the data I needed.

I realized that the PaaS platforms were not a good fit for my needs. I needed something that was more flexible and cost-effective.

I started to look into VPS providers like [OVH](https://www.ovh.com/us/vps/), [Vultr](https://www.vultr.com/) or [Hetzner](https://www.hetzner.com/). The trade-off was that I would have to manage the server myself, but I was willing to do that.

I decided to get a [CAX21](https://www.hetzner.com/cloud) from Hetzner. I'd get 4 vCPUs, 8GB of RAM and 80GB of NVMe storage for €6.49/month, which is a pretty good deal, way better than what I was paying for a PaaS platform.

The server was an Ampere Altra arm64 machine. I decided to go with it versus a similarly priced Intel machine after looking at benchmarks online and seeing that the Altra was a bit faster. When we migrated our main database at work from Heroku to AWS we went with their ARM machines as well and we'd been happy with the results and the cost savings, so I figured it was a good choice.

While configuring the server, they mentioned that I could save €0.50/month by not having a primary IPv4 address. I figured this would be a good opportunity to save money — plus, given the ongoing [IPv4 exhaustion](https://en.wikipedia.org/wiki/IPv4_address_exhaustion), it's a good idea to start migrating over. 

And while I was worried about compatibility issues, I thought that given how long IPv6 has been around, there would be good support for it. 

That ended up not being exactly true. Here's a summary of what happened
<br />
<br />

## Connecting to the server

For all examples in this post, I'll be using addresses from the [documentation prefix](https://en.wikipedia.org/wiki/IPv6_address#Special_addresses) `2001:db8::/32`, which is similar to `192.0.2.0/24` in IPv4.

I provisioned the server with Ubuntu 24.04 LTS and was assigned a `/64` block of IPv6 addresses. The server itself was configured with `2001:db8:1234:5678::1`, the first address in the block, which is a common convention.

After provisioning the server, my immediate next step would normally be to SSH in. However, I couldn't even get a connection. This sent me back to square one: basic network connectivity. My first check was a simple `ping`:


```bash
$ ping 2001:db8:1234:5678::1
ping: cannot resolve 2001:db8:1234:5678::1: Unknown host
```

I was so confused. I wondered if my network didn't support IPv6. I tried to ping a few other addresses in the block, but they all failed.

I found this [IPv6 test page](https://test-ipv6.com/) that I thought would be a good way to test if my network supported IPv6. I ran the test and it said that my network did not support it. 

I was flabbergasted. No IPv6 support in 2025? I started searching and found out that my ISP (Spectrum) is supposed to support it. I then went on my router's settings (Nest Wifi Pro) and found out that it was disabled. I'm not sure if that was the default or I had misguidedly turned it off at some point but I was happy to find the issue. I turned it back on and ran the test again. This time I got a 10/10 score, so I was happy.

I then tried to ping the server again. Still no luck. After doing a bit more digging, turns out there's a separate `ping6` command that I was not using.

```bash
$ ping6 2001:db8:1234:5678::1
PING6(56=40+8+8 bytes) 2001:db8:f00d:face::1 --> 2001:db8:1234:5678::1
16 bytes from 2001:db8:1234:5678::1, icmp_seq=0 hlim=47 time=108.869 ms
```

Finally, success! I could reach the server. Now that I had sorted out the connectivity issues, it was time to deploy the app.

<br />
<br />

## Deploying the app

I decided to use [Dokku](https://dokku.com/) for this. It's a lightweight self-hosted open source PaaS that runs on top of Docker and it's pretty easy to get started with.

I followed the [Dokku documentation](https://dokku.com/docs/getting-started/installation/) to install it. 

```bash
$ wget -NP . https://dokku.com/install/v0.35.20/bootstrap.sh
$ sudo DOKKU_TAG=v0.35.20 bash bootstrap.sh
```

I installed Dokku, set up a domain, and added my SSH key pretty easily. Setting up the domain meant pointing an `AAAA` record to my server's IPv6 address, as a traditional `A` record for IPv4 wouldn't work on an IPv6-only server. My first roadblock came when I tried to provision a Postgres database. Postgres is not supported out of the box, but there's a plugin for that.

```bash
$ sudo dokku plugin:install https://github.com/dokku/dokku-postgres.git
-----> Cloning plugin repo https://github.com/dokku/dokku-postgres.git to /var/lib/dokku/plugins/available/postgres
Cloning into 'postgres'...

fatal: unable to access 'https://github.com/dokku/dokku-postgres.git/': Failed to connect to github.com port 443 after 2 ms: Couldn't connect to server
```

I was confused. I verified I had a working internet connection. I pinged `github.com` from my local machine and it was working. I pinged it from the server and it was not.

It turns out GitHub does not support IPv6 at all. There's a [discussion thread](https://github.com/orgs/community/discussions/10539) with hundreds of replies in the GitHub Community forum, but so far no official announcement. There's even a website called [isgithubipv6.live](https://isgithubipv6.live/) that you can sign up for to get notified when they enable it.

I wasn't gonna wait for that to happen, and luckily I found a workaround. There's a proxy called [gh-v6.com](https://gh-v6.com/) that allows you to access repositories over IPv6. And Dokku has a way to manually specify a URL for plugin installations.

```bash
$ sudo dokku plugin:install https://gh-v6.com/dokku/dokku-postgres/archive/refs/tags/1.44.0.tar.gz --name dokku-postgres
-----> Installing plugin dokku-postgres (1.44.0)
```

Note that this proxy only works for release assets, so I had to specify the version of the plugin I wanted to install. I also had to specify the name of the plugin with the `--name` flag, otherwise Dokku would assume my plugin was called `1.44.0.tar.gz`. 

I was able to install the plugin and create an app and a database, and link them together.

```bash
$ dokku apps:create my-app
$ dokku postgres:create my-app-database
$ dokku postgres:link my-app-database my-app
```

With a `Dockerfile` and a `Procfile` in place, I was ready to deploy. Dokku keeps the simple `git push` workflow popularized by Heroku, so after setting up a git remote, I could deploy my app with a single command:

```bash
cd my-app
git remote add dokku dokku@example.com:my-app
git push dokku main
```

Here, `example.com` should be the domain you pointed to your server's IPv6 address with an AAAA record.

However, this is where I hit another roadblock. I was not able to build the app. I was getting the following error when downloading a gem:

```
SocketError: Failed to open TCP connection to rubygems.org:443 (Hostname not known: rubygems.org) (https://rubygems.org/specs.4.8.gz)
```

My mind immediately thought it was the same issue as GitHub: lack of IPv6 support. However, I was able to ping `rubygems.org` from the server, so I eliminated that possibility. I went online and found out the problem was that Docker does not enable IPv6 by default.

I had to configure the Docker daemon to support IPv6 by editing `/etc/docker/daemon.json`. This file might not exist by default, so you may need to create it. Since I was allocated a /64 block of IPv6 addresses, I used a smaller /80 subnet for Docker to avoid conflicts with host networking:

```json
{
  "ipv6": true,
  "fixed-cidr-v6": "2001:db8:1234:5678:1000::/80"
}
```

This reserves a /80 subnet (281 trillion addresses) for Docker containers while leaving the rest of my /64 allocation available for other uses.

Then I restarted Docker:
```bash
$ sudo systemctl restart docker
```

For Dokku apps to work with IPv6, I needed to configure the app to bind to all interfaces instead of just localhost:

```bash
$ dokku network:set my-app bind-all-interfaces true
```

Then rebuild the app to apply the network changes:

```bash
$ dokku ps:rebuild my-app
```

That's it! The `bind-all-interfaces` setting ensures the app listens on `[::]:PORT` (all IPv6 interfaces) rather than just `127.0.0.1:PORT` (IPv4 localhost only), which is essential for IPv6-only servers.

My app was now running on IPv6. I was able to access it from my local machine and from the internet. I wanted to enable SSL, and Dokku provides a plugin to get a certificate automatically using [Let's Encrypt](https://letsencrypt.org/). Luckily, their validation process worked perfectly over IPv6, but I still had to use the proxy to install the plugin:

```bash
$ sudo dokku plugin:install https://gh-v6.com/dokku/dokku-letsencrypt/archive/refs/tags/0.22.0.tar.gz --name letsencrypt
$ sudo dokku letsencrypt:cron-job --add
$ dokku letsencrypt:set my-app email email@example.com
$ dokku letsencrypt:enable my-app
```

I was done! I was able to access my app over HTTPS, both from my local machine and from the internet.

<br />
<br />

## Conclusion

So, was saving €0.50 a month by going IPv6-only worth the trouble? Absolutely. While the journey wasn't as straightforward as I'd initially hoped, it highlights that the internet is in a transition period. The core IPv6 technology is solid, but tools like GitHub and Docker still require manual configuration or workarounds to function in an IPv6-only world.

The key challenges I faced were:
1.  Fixing my own local network's lack of IPv6 support.
2.  Using a proxy to pull Dokku plugins from GitHub.
3.  Manually enabling IPv6 in Docker's configuration.

Despite these hurdles, I now have a cost-effective, high-performance, and future-proof platform for my projects. If you're considering making the jump, I'd say go for it. The challenges are surmountable, and by navigating them, you'll be a little bit ahead of the curve.
