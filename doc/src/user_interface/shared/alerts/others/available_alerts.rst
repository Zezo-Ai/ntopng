.. _BehaviouralChecks:

Behavioural Checks
==================

Checks are executed for hosts, interfaces, SNMP devices, and other network elements, and are configurable under Checks from the Settings left sidebar.

.. figure:: ../../../../img/alerts_checks_management.png
  :align: center
  :alt: Checks Configuration
  
Checks are desiged to verify specific conditions and when they are not met, trigger an alert. 

Interface Types
~~~~~~~~~~~~~~~

Checks can be available on both, ZMQ Interfaces and Packets Interfaces, or just on one of them;

.. |packet_interface| image:: ../../../../img/packet_interface_icon.png

- Packet interface: |packet_interface|

.. |zmq_interface| image:: ../../../../img/zmq_interface_icon.png

- ZMQ interface: |zmq_interface|


Alerts List
~~~~~~~~~~~

Below, the list of all the available alerts divided per family and which license is needed for each one.

.. toctree::
    :maxdepth: 2

    alerts_list_per_license
    host_checks
    interface_checks
    local_network_checks
    snmp_checks
    flow_checks
    system_checks
    active_monitoring_checks
    syslog_checks
    

