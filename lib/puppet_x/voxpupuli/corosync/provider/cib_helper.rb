require File.join(File.dirname(__FILE__), '..','..','..','..','puppet_x/voxpupuli/corosync/provider')

class PuppetX::Voxpupuli::Corosync::Provider::CibHelper < Puppet::Provider
  # Yep, that's right we are parsing XML...FUN! (It really wasn't that bad)
  require 'rexml/document'

  def self.run_command_in_cib(cmd, cib = nil, failonfail = true)
    custom_environment = if cib.nil?
                           { combine: true }
                         else
                           { combine: true, custom_environment: { 'CIB_shadow' => cib } }
                         end
    debug("Executing #{cmd} in the CIB") if cib.nil?
    debug("Executing #{cmd} in the shadow CIB \"#{cib}\"") unless cib.nil?
    raw = Puppet::Util::Execution.execute(cmd, { failonfail: failonfail }.merge(custom_environment))
    status = raw.exitstatus
    return raw, status if status.zero? || failonfail == false
    raise Puppet::Error, "Command #{cmd.join(' ')} failed" if cib.nil?
    raise Puppet::Error, "Command #{cmd.join(' ')} failed in the shadow CIB \"#{cib}\"" unless cib.nil?
  end

  # given an XML element containing some <nvpair>s, return a hash. Return an
  # empty hash if `e` is nil.
  def self.nvpairs_to_hash(e)
    return {} if e.nil?

    hash = {}
    e.each_element do |i|
      hash[i.attributes['name']] = i.attributes['value'].strip
    end

    hash
  end

  # The node2hash method maps resource locations from XML into hashes.
  # An anonymous hash is returned for node names given in `anon_hash_nodes`.
  def self.node2hash(node, anon_hash_nodes = [])
    attr = {}
    name = ''

    return nil unless node.instance_of? REXML::Element

    # Add attributes from the node
    node.attributes.each do |key, val|
      if key == 'id'
        name = val
      else
        attr[key] = val
      end
    end

    # Traverse elements in the XML tree recursively
    node.elements.each do |child|
      attr[child.name] = [] unless attr[child.name].is_a? Array
      attr[child.name] << node2hash(child, anon_hash_nodes)
    end

    # Return only the attributes if requested and a hash otherwise
    anon_hash_nodes.include?(node.name) ? attr : { name => attr }
  end

  # Generate a string with the rule expression
  # - rulename is the name of the rule (used in error messages)
  # - expressions is an array of expressions as returned by node2hash()
  # - boolean_op is the operator; this must be either 'and' or 'or'
  def self.rule_expression(rulename, expressions, boolean_op = 'and')
    rule_parameters = []
    count = 0

    if boolean_op != 'and' && boolean_op != 'or'
      raise Puppet::Error, "boolean-op must be 'and' or 'or' in rule #{rulename}"
    end

    expressions.each do |expr|
      rule_parameters << boolean_op if count > 0
      count += 1

      if expr['attribute'].nil?
        raise Puppet::Error, "attribute must be defined for expression #{count} in rule #{rulename}"
      end

      if expr['operation'].nil?
        raise Puppet::Error, "operation must be defined for expression #{count} in rule #{rulename}"
      end

      attribute = expr['attribute']
      operation = expr['operation']

      case operation
      when 'defined', 'not_defined'
        rule_parameters << operation
        rule_parameters << attribute

      when 'lt', 'gt', 'lte', 'gte', 'eq', 'ne'
        if expr['value'].nil?
          raise Puppet::Error, "value must be defined for expression #{count} in rule #{rulename}"
        end

        rule_parameters << attribute
        rule_parameters << operation
        rule_parameters << expr['value']

      else
        # FIXME: time- and date-based expressions not yet implemented
        raise Puppet::Error, "illegal operation '#{operation}' for expression #{count} in rule #{rulename}"
      end
    end

    rule_parameters
  end

  def self.sync_shadow_cib(cib, failondeletefail = false)
    run_command_in_cib(['crm_shadow', '--force', '--delete', cib], nil, failondeletefail)
    run_command_in_cib(['crm_shadow', '--batch', '--create', cib])
  end

  def self.get_epoch(cib = nil)
    cmd = [command(:cibadmin), '--query', '--xpath', '/cib', '-l', '-n']
    raw, status = run_command_in_cib(cmd, cib, false)
    return :absent if status.nonzero?
    doc = REXML::Document.new(raw)
    current_epoch = REXML::XPath.first(doc, '/cib').attributes['epoch']
    current_admin_epoch = REXML::XPath.first(doc, '/cib').attributes['admin_epoch']
    currentvalue = "#{current_admin_epoch}.#{current_epoch}" if current_epoch && current_admin_epoch
    currentvalue || :absent
  end

  # This function waits for the epoch to be different than 0.0
  # different than :absent. Returns the value of the epoch as soon an it is present and
  # different that 0.0 or eventually returns the value after a certain time.
  def self.wait_for_nonzero_epoch(shadow_cib)
    begin
      Timeout.timeout(60) do
        if shadow_cib
          epoch = get_epoch
          while epoch == :absent || epoch.start_with?('0.')
            sleep 2
            epoch = get_epoch
          end
        else
          sleep 2 while ['0.0', :absent].include?(get_epoch)
        end
      end
    rescue Timeout::Error
      debug('Timeout reached while fetching a relevant epoch')
    end
    get_epoch
  end
end
