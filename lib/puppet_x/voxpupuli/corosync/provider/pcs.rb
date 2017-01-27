require File.join(File.dirname(__FILE__), '..','..','..','..','puppet_x/voxpupuli/corosync/provider')
require File.join(File.dirname(__FILE__), '..','..','..','..','puppet_x/voxpupuli/corosync/provider/cib_helper')

class PuppetX::Voxpupuli::Corosync::Provider::Pcs < PuppetX::Voxpupuli::Corosync::Provider::CibHelper
  initvars
  commands cibadmin: 'cibadmin'
  commands pcs: 'pcs'

  # Corosync takes a while to build the initial CIB configuration once the
  # service is started for the first time.  This provides us a way to wait
  # until we're up so we can make changes that don't disappear in to a black
  # hole.
  # rubocop:disable Style/ClassVars
  @@pcsready = nil
  # rubocop:enable Style/ClassVars
  def self.ready?(shadow_cib)
    return true if @@pcsready
    cmd = [command(:pcs), 'property', 'show', 'dc-version']
    raw, status = run_command_in_cib(cmd, nil, false)
    if status.zero?
      # Wait until epoch is not 0.0.
      # On empty cluster it will stay 0.0 so there you wait the 60 seconds.
      # On new nodes you wait just enough time to allow the node to join the cluster.
      # That should not happen often, so it is acceptable to sleep up to 60 seconds here.
      cib_epoch = wait_for_nonzero_epoch(shadow_cib)

      warn("Pacemaker: CIB epoch is #{cib_epoch}. You can ignore this message if you are bootstrapping a new cluster.") if cib_epoch == '0.0'

      if cib_epoch == :absent
        debug('Corosync is not ready (no CIB available)')
        return false
      end

      # rubocop:disable Style/ClassVars
      @@pcsready = true
      # rubocop:enable Style/ClassVars

      debug("Corosync is ready, CIB epoch is #{cib_epoch}. Sleeping 5 seconds for safety.")
      sleep 5
      return true
    else
      debug("Corosync not ready, retrying: #{raw}")
      return false
    end
  end

  def self.block_until_ready(timeout = 120, shadow_cib = false)
    Timeout.timeout(timeout) do
      sleep 2 until ready?(shadow_cib)
    end
  end

  def self.prefetch(resources)
    instances.each do |prov|
      # rubocop:disable Lint/AssignmentInCondition
      if res = resources[prov.name.to_s]
        # rubocop:enable Lint/AssignmentInCondition
        res.provider = prov
      end
    end
  end

  def exists?
    self.class.block_until_ready
    debug(@property_hash.inspect)
    !(@property_hash[:ensure] == :absent || @property_hash.empty?)
  end
end
