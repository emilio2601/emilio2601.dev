---
layout: narrative
title: "Deploying a Web App on an Affordable IPv6-Only VPS"
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
Recently, I needed a home for a new personal project. While I love the simplicity of [GitHub Pages](https://pages.github.com/) – where this blog lives – a dynamic Rails application requires a bit more firepower.

A PaaS was the obvious starting point. [Heroku](https://www.heroku.com/) was the platform I knew best, but my professional experience migrating a team away from it due to cost and stability issues made me hesitant to use it personally. Instead, I decided this was the perfect opportunity to see what the modern PaaS landscape had to offer.

My first stop was [Render](https://render.com). It was pretty easy to get my app up and running on their basic plan, but as soon as I tried to load my initial dataset the import process repeatedly failed, hitting memory limits.

The obvious path forward was to upgrade, but I was already questioning the value. For $27/month, my app had just 512MB of RAM, with another 1GB for the database. This wasn't nearly enough, yet the dataset itself was tiny: a year's worth of data (~400,000 rows) is only about 150MB in an uncompressed CSV. It seemed absurd to pay more for a platform that couldn't handle such a small initial load, so I decided to look elsewhere.

This wasn't just a Render-specific issue; it was a fundamental problem with the PaaS model for a resource-hungry hobby project. A quick survey of other providers confirmed this. They all charge a premium for the convenience of a managed platform, with RAM and CPU being the most expensive, metered resources. It was clear that simply switching to another PaaS would lead to the same dead end: paying too much for too little.

That's when I realized I needed to trade convenience for control and started looking into VPS providers like [OVH](https://www.ovh.com/us/vps/), [Vultr](https://www.vultr.com/), or [Hetzner](https://www.hetzner.com/). The deal was simple: I would have to manage the server myself, but in return, I'd get far more raw power for my money. It was a trade-off I was happy to make.

I ultimately chose a [CAX21](https://www.hetzner.com/cloud) from Hetzner, which offered an incredible amount of power for the price: 4 vCPUs, 8GB of RAM, and 80GB of NVMe storage for just €6.49/month.

This specific server came with an Ampere Altra processor, which brought up a key decision: should I go with ARM or a similarly-priced Intel machine? I opted for ARM for a few reasons. My professional experience was positive – we had successfully migrated our main database at work to AWS's ARM-based Graviton instances with great results. My personal setup was also a factor; developing on an Apple M4 Mac meant I was already confident that every dependency for this project was ARM-compatible. With online benchmarks giving the Altra a performance edge anyway, the decision felt solid.

While configuring the server, Hetzner offered a €0.50/month rebate if I didn't want a primary IPv4 address. It seemed like a no-brainer: besides the small discount, it felt like a forward-thinking choice in the face of [IPv4 exhaustion](https://en.wikipedia.org/wiki/IPv4_address_exhaustion). 

I brushed aside any worries about compatibility. After all, IPv6 has been around for decades. Surely support would be nearly universal by now?

Not exactly.
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

A check on [test-ipv6.com](https://test-ipv6.com/) showed that my home network lacked IPv6 support, which was surprising given my ISP (Spectrum in New York City) is supposedly IPv6-capable.

The culprit, it turned out, was an embarrassingly simple toggle buried in my Nest Wifi Pro's settings. I'm not sure if it was the default or a past misconfiguration, but flipping it on, restarting the router and re-running the test granted me a perfect 10/10. With the local issue resolved, I moved on.

Even with local IPv6 connectivity confirmed, `ping` still failed to reach the server. It turned out the problem wasn't the network, but the tool. On many systems, `ping` and `ping6` are separate commands. The former defaults to or is exclusively for IPv4, while `ping6` must be used to send ICMPv6 echo requests. This separation is a historical artifact from the internet's gradual transition, ensuring that older, IPv4-centric tools and scripts remained compatible.

```bash
$ ping6 2001:db8:1234:5678::1
PING6(56=40+8+8 bytes) 2001:db8:f00d:face::1 --> 2001:db8:1234:5678::1
16 bytes from 2001:db8:1234:5678::1, icmp_seq=0 hlim=47 time=108.869 ms
```

Finally, success! I could reach the server. Now that I had sorted out the connectivity issues, it was time to deploy the app.

<br />

## Deploying the app

My decision to use a VPS solved the cost and resource problem, but it introduced a new one: developer experience. I didn't want to trade the convenience of a managed platform for a world of manual configuration. I had no desire to set up Nginx, manage system processes, and script deployments by hand.

This is the exact problem a self-hosted PaaS is designed to solve. After some research, I chose [Dokku](https://dokku.com/). It's a lightweight, open-source project that runs on my server and automates all the tedious parts of deployment. It handles everything from building the application inside a container to configuring the web server and managing environment variables. Its plugin system even lets me provision services like a Postgres database or an SSL certificate with a single command, effectively giving me a private, powerful, and cost-effective app platform on hardware I control.

Their [documentation](https://dokku.com/docs/getting-started/installation/) was pretty easy to follow, and I was able to install it in a few minutes.

```bash
$ wget -NP . https://dokku.com/install/v0.35.20/bootstrap.sh
$ sudo DOKKU_TAG=v0.35.20 bash bootstrap.sh
```

After installing the main package, I added my SSH key and set up my domain. This meant pointing an `AAAA` record to my server's IPv6 address, as a traditional `A` record for IPv4 wouldn't work on an IPv6-only server. My first issue came when I tried to install their Postgres plugin.

```bash
$ sudo dokku plugin:install https://github.com/dokku/dokku-postgres.git
-----> Cloning plugin repo https://github.com/dokku/dokku-postgres.git to /var/lib/dokku/plugins/available/postgres
Cloning into 'postgres'...

fatal: unable to access 'https://github.com/dokku/dokku-postgres.git/': Failed to connect to github.com port 443 after 2 ms: Couldn't connect to server
```

I was confused. I verified I had a working internet connection. I successfully pinged `github.com` from my local machine, so I knew their service was up. However, when I tried to reach their servers from my VPS, I couldn't connect at all.

It turns out that as of August 2025, GitHub's IPv6 support is incomplete. While some services like GitHub Pages are accessible over IPv6, core functionality including the website itself and `git` operations remains IPv4-only. There's a [discussion thread](https://github.com/orgs/community/discussions/10539) with hundreds of replies in the GitHub Community forum, but so far no official announcement. There's even a tracker website called [isgithubipv6.live](https://isgithubipv6.live/) with a signup form to get notified when they enable it.

I wasn't gonna wait for that to happen, and luckily I found a workaround. There's a proxy called [gh-v6.com](https://gh-v6.com/) that allows you to access repositories over IPv6. And Dokku has a way to manually specify a URL for plugin installations.

```bash
$ sudo dokku plugin:install https://gh-v6.com/dokku/dokku-postgres/archive/refs/tags/1.44.0.tar.gz --name dokku-postgres
-----> Installing plugin dokku-postgres (1.44.0)
```

Note that this proxy only works for release assets, so I had to specify the URL for the specific version of the plugin I wanted to install. I also had to specify the name of the plugin with the `--name` flag, otherwise Dokku would assume my plugin was called `1.44.0.tar.gz`. 

I was able to install the plugin and create an app and a database, and link them together.

```bash
$ dokku apps:create my-app
$ dokku postgres:create my-app-database
$ dokku postgres:link my-app-database my-app
```

With the application and database now provisioned on the server, I could switch back to my local machine. To make remote management easier, Dokku also provides a client that can be installed locally. On macOS, it's a simple Homebrew command:

```bash
$ brew install dokku/repo/dokku
```

This client allows you to run commands against your server over SSH, providing a seamless CLI experience for management tasks - just like you would with the Heroku CLI or any other major PaaS.

With a `Dockerfile` and a `Procfile` in place, I was ready to deploy. Dokku keeps the simple `git push` workflow popularized by Heroku, so after setting up a git remote, I could deploy my app with a single command:

```bash
$ cd my-app
$ git remote add dokku dokku@example.com:my-app
$ git push dokku main
```

Here, `example.com` refers to the domain that points to the server's IPv6 address with an `AAAA` record.

However, this is where I hit another roadblock. I was not able to build the app. The build process errored halfway through, with the following message:

```
SocketError: Failed to open TCP connection to rubygems.org:443 (Hostname not known: rubygems.org) (https://rubygems.org/specs.4.8.gz)
```

My mind immediately thought it was the same issue as GitHub: lack of IPv6 support. However, I was able to ping `rubygems.org` from the server, so I eliminated that possibility.

This is where I ran into an important distinction: the host server's network is not the same as the network inside a Docker container. My application build wasn't running on the host directly; it was running inside an isolated container. By default, Docker doesn't enable IPv6 on its internal networks. So, while my server could see the wider IPv6 internet, the build container was trapped in an IPv4-only world. Any attempt to reach an IPv6 address from within it was doomed to fail.

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

For Dokku apps to work with IPv6, I needed to configure the app to bind to all interfaces instead of just localhost. This setting ensures the app listens on `[::]:PORT` (all IPv6 interfaces) rather than just `127.0.0.1:PORT` (IPv4 localhost only), which is essential for IPv6-only servers.

```bash
$ dokku network:set my-app bind-all-interfaces true
```

Then rebuild the app to apply the network changes:

```bash
$ dokku ps:rebuild my-app
```

That's it! The only thing remaining was to make it accessible over HTTPS. Dokku provides a plugin to get a certificate automatically using [Let's Encrypt](https://letsencrypt.org/). Even though I still had to use the `gh-v6.com` proxy to install it, their validation process worked perfectly over IPv6:

```bash
$ sudo dokku plugin:install https://gh-v6.com/dokku/dokku-letsencrypt/archive/refs/tags/0.22.0.tar.gz --name letsencrypt
$ sudo dokku letsencrypt:cron-job --add
$ dokku letsencrypt:set my-app email email@example.com
$ dokku letsencrypt:enable my-app
```

I was done! I was able to access my app over HTTPS, both locally and from the internet.

<br />

## Conclusion

When I started this project, my main goal was to escape the limitations and high costs of commercial PaaS platforms. The IPv6-only server was initially just a way to save a few cents, but this journey revealed a much bigger win. It turns out, you don't have to choose between a polished, `git push`-to-deploy workflow and the freedom of your own hardware. By pairing a tool like Dokku with an affordable VPS, you can have both.

The final piece of this setup, and what makes it so practical, is using Cloudflare as a proxy. This gives you the best of both worlds. My server gets to be lean and modern, running only on IPv6—which means a simpler configuration and a smaller attack surface. At the same time, anyone on the internet can access my site because Cloudflare handles the messy business of translating legacy IPv4 traffic. It’s a clean, secure backend with universal access, and a powerful blueprint for any modern web application.

<br />