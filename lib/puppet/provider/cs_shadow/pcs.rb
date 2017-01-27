require File.join(File.dirname(__FILE__), '..','..','..','puppet_x/voxpupuli/corosync/provider/pcs')

Puppet::Type.type(:cs_shadow).provide(:pcs, parent: PuppetX::Voxpupuli::Corosync::Provider::Pcs) do
  commands crm_shadow: 'crm_shadow'
  commands cibadmin: 'cibadmin'
  # Required for block_until_ready
  commands pcs: 'pcs'

  def self.instances
    block_until_ready(120, true)
    []
  end

  # Need this available at the provider level, for types
  def get_epoch(cib = nil)
    PuppetX::Voxpupuli::Corosync::Provider::Pcs.get_epoch(cib)
  end

  def epoch
    get_epoch(resource.cib)
  end

  def insync?(cib)
    get_epoch == get_epoch(cib)
  end

  def sync(_cib)
    PuppetX::Voxpupuli::Corosync::Provider::Pcs.sync_shadow_cib(@resource[:name])
  end
end
