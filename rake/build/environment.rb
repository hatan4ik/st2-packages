#!/usr/bin/env ruby
require 'hashie'
require 'resolv'

# Defines options for the build pipeline
#

# Set global pipeline options
pipeopts do
  ssh_options({
    keys: %w(/root/.ssh/busybee),
    auth_methods: %w(publickey)
  })

  env     :buildnode
  env     :testnode
  envpass :testmode, 'bundle' # components || bundle
  envpass :basedir,  '/root'
  envpass :debug_level, 1
  envpass :artifact_dir, '/root/build'    # make it temp??

  # Target directory for intermidiate files (on the remotes!)
  envpass :wheeldir, '/tmp/wheelhouse'

  # Single package in a gitdir is standalone
  standalone true
  checkout :st2, :mistral
  upload_sources 'packages', 'scripts', 'rpmspec'

  # Services host variables
  [:rabbitmq, :mongodb, :postgres].each {|n| envpass "#{n}host", n.to_s}

  # This that what we want to build
  packages  :st2common, :st2actions, :st2api, :st2auth, :st2client,
            :st2reactor, :st2exporter, :st2debug, :st2bundle, :mistral
end

pipeopts 'st2python' do
  envpass :st2_python, 0
  envpass :st2_python_version, '2.7.10'
  envpass :st2_python_relase, 1
end

pipeopts 'st2' do
  # st2 packages are not standalone (ie. there are many $gitdir/st2*)
  standalone false
  checkout :st2
  envpass :giturl,   'https://github.com/StackStorm/st2', from: 'ST2_GITURL'
  envpass :gitrev,   'master',                            from: 'ST2_GITREV'
  envpass :gitdir,    make_tmpname('st2-'),               from: 'ST2_GITDIR'
  envpass :st2pkg_version
  envpass :st2pkg_release, 1
end

pipeopts 'mistral' do
  checkout :mistral
  envpass :giturl,  'https://github.com/StackStorm/mistral', from: 'MISTRAL_GITURL'
  envpass :gitrev,  'st2-1.1.0',                             from: 'MISTRAL_GITREV'
  envpass :gitdir,  make_tmpname('mistral-')
  envpass :mistral_version, '1.1.0'
  envpass :mistral_release, 1
end

## Choose packages to test
pipeopts.packages.dup.tap do |list|
  if pipeopts.testmode == 'components'
    list.delete!(:st2bundle)
  elsif list.include?(:st2bundle)
    list.select! {|p| not p.to_s.start_with?('st2')}
    list << :st2bundle
  end
  pipeopts[:testing_list] = list
end

## Serverspec or netcat work in a buggy fashion,
#  we have to resolve remotes
[:rabbitmq, :mongodb, :postgres].map{|n| :"#{n}host"}.each do |remote|
  value = pipeopts[remote].to_s
  unless value =~ Resolv::AddressRegex
    pipeopts[remote] = Resolv.getaddress(value)
    pipeopts.env[remote.upcase] = Resolv.getaddress(value)
  end
end